// Created 2026-09-15 · gpt-6-astra · Codex
import AppKit
import Combine
import StillCore
import UserNotifications

struct LocalArchive: Codable {
    var version = 2
    var timer = TimerState()
    var sessions: [FocusSession] = []
    var preferences = Preferences()
}

private struct JournalSyncRequest: Sendable {
    let path: String
    let pathIntent: Int
    let sessionRevision: Int
    let sessions: [FocusSession]
    let adoptsPath: Bool
    let createsIfMissing: Bool
}

private enum JournalSyncResult: Sendable {
    case success([FocusSession])
    case failure(String)
}

@MainActor
final class AppModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var timer = TimerState()
    @Published private(set) var sessions: [FocusSession] = []
    @Published var preferences = Preferences()
    @Published private(set) var now = Date()
    @Published var storageError: String?
    @Published var notificationStatus = "Not requested"
    @Published var journalError: String?
    @Published private(set) var journalIsBusy = false
    var onWindowPreferencesChanged: (() -> Void)?
    private var pulse: AnyCancellable?
    private var sound: NSSound?
    private var notificationGeneration = 0
    private var hasNotificationPermission = false
    private var systemChimeScheduled = false
    private var canSave = true
    private var journalPathIntent = 0
    private var pendingJournalPath: String?
    private var journalSessionRevision = 0
    private var queuedJournalRequests: [String: JournalSyncRequest] = [:]
    private var activeJournalPaths: Set<String> = []
    private var journalPathWaiters: [Int: CheckedContinuation<Bool, Never>] = [:]
    let dataURL: URL
    let isPreview: Bool
    let inspiration: InspirationStore

    init(dataDirectory: URL? = nil, preview: Bool = false, syncJournalOnLaunch: Bool = true) {
        isPreview = preview
        dataURL = (dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Still", isDirectory: true)).appendingPathComponent("state.json")
        inspiration = InspirationStore(directory: dataURL.deletingLastPathComponent(), preview: preview)
        super.init()
        if !preview { load() }
        let hadStoredJournalPath = !preferences.journalPath.isEmpty
        if preferences.journalPath.isEmpty {
            let directory = dataDirectory != nil ? dataURL.deletingLastPathComponent() : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            preferences.journalPath = directory.appendingPathComponent("Still-sessions.md").path
        }
        UNUserNotificationCenter.current().delegate = self
        // Reconcile a deadline that elapsed while Still was closed, without replaying an old chime.
        let restoringRunningTimer = timer.phase == .running
        if let session = timer.tick(at: now) { add(session) }
        if restoringRunningTimer && timer.phase == .completed { persist() }
        pulse = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] date in
            self?.advance(to: date)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        if !preview {
            // The existence check and any Markdown I/O run on the journal worker. A
            // newly generated default path with no sessions is intentionally untouched.
            if syncJournalOnLaunch && (!sessions.isEmpty || hadStoredJournalPath) { synchronizeJournal() }
            Task { await refreshNotificationStatus() }
            if timer.phase == .running { syncNotification(requestPermission: false) }
        }
    }

    var remaining: Int { max(0, Int(ceil(timer.remaining(at: now)))) }
    var minutes: String { String(format: "%02d", remaining / 60) }
    var seconds: String { String(format: "%02d", remaining % 60) }
    var progress: Double { min(1, max(0, 1 - timer.remaining(at: now) / timer.duration)) }
    var todaySessions: [FocusSession] { sessions.filter { Calendar.current.isDate($0.completedAt, inSameDayAs: now) } }
    var todayMinutes: Int { Int(todaySessions.reduce(0) { $0 + $1.duration } / 60) }
    var totalMinutes: Int { Int(sessions.reduce(0) { $0 + $1.duration } / 60) }
    var isInProgress: Bool { timer.phase == .running || timer.phase == .paused }
    var primaryTitle: String {
        switch timer.phase {
        case .running: return "Pause"
        case .paused: return "Continue"
        case .completed: return timer.mode == .focus ? "Take a breath" : "Back to focus"
        case .ready: return timer.mode == .focus ? "Begin focus" : "Begin rest"
        }
    }
    var subtitle: String {
        switch timer.phase {
        case .running: return timer.mode == .focus ? "One thing at a time." : "A little room to breathe."
        case .paused: return "Here when you’re ready."
        case .completed: return timer.mode == .focus ? "A little more, well done." : "A fresh beginning."
        case .ready: return timer.mode == .focus ? "Make room for what matters." : "Rest is part of the rhythm."
        }
    }

    func duration(for mode: TimerMode) -> TimeInterval {
        switch mode {
        case .focus: return Double(preferences.focusMinutes * 60)
        case .shortBreak: return Double(preferences.shortBreakMinutes * 60)
        case .longBreak: return Double(preferences.longBreakMinutes * 60)
        }
    }
    func primaryAction() {
        advance(to: Date())
        switch timer.phase {
        case .running: timer.pause(at: now)
        case .ready, .paused: timer.start(at: now)
        case .completed:
            let next: TimerMode = timer.mode == .focus ? (todaySessions.count % 4 == 0 ? .longBreak : .shortBreak) : .focus
            timer.configure(mode: next, duration: duration(for: next))
            timer.start(at: now)
        }
        persist()
        syncNotification(requestPermission: timer.phase == .running)
    }
    func startFocus(minutes: Int) {
        guard !isInProgress else { return }
        now = Date()
        timer.configure(mode: .focus, duration: Double(min(180, max(1, minutes)) * 60))
        timer.start(at: now)
        persist()
        syncNotification(requestPermission: true)
    }
    func startBreak(_ mode: TimerMode) {
        guard !isInProgress, mode != .focus else { return }
        now = Date()
        timer.configure(mode: mode, duration: duration(for: mode))
        timer.start(at: now)
        persist()
        syncNotification(requestPermission: true)
    }
    func selectMode(_ mode: TimerMode) {
        guard !isInProgress else { return }
        timer.configure(mode: mode, duration: duration(for: mode))
        now = Date()
        persist()
        syncNotification(requestPermission: false)
    }
    func reset() {
        timer.configure(mode: timer.mode, duration: duration(for: timer.mode))
        now = Date()
        persist()
        syncNotification(requestPermission: false)
    }
    func savePreferences() {
        preferences.sanitize()
        if timer.phase == .ready { timer.configure(mode: timer.mode, duration: duration(for: timer.mode)) }
        persist()
        onWindowPreferencesChanged?()
        syncNotification(requestPermission: false)
    }
    func advance(to date: Date) {
        now = date
        let wasRunning = timer.phase == .running
        if let session = timer.tick(at: date) { add(session); persist(); synchronizeJournal() }
        if wasRunning && timer.phase == .completed {
            persist()
            if preferences.soundEnabled && !systemChimeScheduled { playChime() }
        }
    }
    @objc private func woke() { advance(to: Date()) }
    private func add(_ session: FocusSession) {
        if !sessions.contains(where: { $0.id == session.id }) {
            sessions.append(session)
            journalSessionRevision += 1
        }
    }
    var journalDisplayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return preferences.journalPath.hasPrefix(home + "/") ? "~" + preferences.journalPath.dropFirst(home.count) : preferences.journalPath
    }
    @discardableResult
    func setJournalPath(_ path: String) -> Bool {
        guard !isPreview else { preferences.journalPath = path; return true }
        guard let normalizedPath = normalizedJournalPath(path) else { return false }
        let intent = beginJournalPathChange(to: normalizedPath)
        let url = URL(fileURLWithPath: normalizedPath)
        do {
            let existing = FileManager.default.fileExists(atPath: url.path) ? try MarkdownJournal.read(from: url) : []
            let merged = Self.mergedSessions(sessions, existing)
            try MarkdownJournal.synchronize(sessions: merged, to: url)
            if merged.count != sessions.count { journalSessionRevision += 1 }
            sessions = merged
            preferences.journalPath = normalizedPath
            pendingJournalPath = nil
            journalError = nil
            persist()
            refreshJournalBusy()
            return true
        } catch {
            if intent == journalPathIntent {
                pendingJournalPath = nil
                journalError = "Could not use this Markdown file: \(error.localizedDescription)"
                refreshJournalBusy()
            }
            return false
        }
    }

    /// Nonblocking UI path selection. The returned value is available after the
    /// background worker has validated and synchronized the requested Markdown file.
    func setJournalPathAsync(_ path: String) async -> Bool {
        guard !isPreview else { preferences.journalPath = path; return true }
        guard let normalizedPath = normalizedJournalPath(path) else { return false }
        let intent = beginJournalPathChange(to: normalizedPath)

        return await withCheckedContinuation { continuation in
            journalPathWaiters[intent] = continuation
            enqueueJournalSync(
                path: normalizedPath,
                intent: intent,
                adoptsPath: true,
                createsIfMissing: true
            )
        }
    }

    private func synchronizeJournal() {
        guard !isPreview else { return }
        let path = pendingJournalPath ?? preferences.journalPath
        guard !path.isEmpty else { return }
        enqueueJournalSync(
            path: path,
            intent: journalPathIntent,
            adoptsPath: pendingJournalPath == path,
            createsIfMissing: !sessions.isEmpty || pendingJournalPath == path
        )
    }

    private func normalizedJournalPath(_ path: String) -> String? {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), !expanded.isEmpty else {
            journalError = "Choose an absolute path ending in .md."
            return nil
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private var currentJournalTargetPath: String {
        pendingJournalPath ?? preferences.journalPath
    }

    private func beginJournalPathChange(to path: String) -> Int {
        journalPathIntent += 1
        let intent = journalPathIntent
        pendingJournalPath = path
        for continuation in journalPathWaiters.values {
            continuation.resume(returning: false)
        }
        journalPathWaiters.removeAll()
        queuedJournalRequests = queuedJournalRequests.filter { $0.value.pathIntent == intent }
        journalError = nil
        refreshJournalBusy()
        return intent
    }

    private func enqueueJournalSync(path: String, intent: Int, adoptsPath: Bool, createsIfMissing: Bool) {
        guard intent == journalPathIntent, path == currentJournalTargetPath else { return }
        queuedJournalRequests[path] = JournalSyncRequest(
            path: path,
            pathIntent: intent,
            sessionRevision: journalSessionRevision,
            sessions: sessions,
            adoptsPath: adoptsPath,
            createsIfMissing: createsIfMissing
        )
        startQueuedJournalSync(for: path)
        refreshJournalBusy()
    }

    private func startQueuedJournalSync(for path: String) {
        guard !activeJournalPaths.contains(path), let request = queuedJournalRequests.removeValue(forKey: path) else { return }
        guard isCurrentJournalRequest(request) else {
            refreshJournalBusy()
            return
        }

        activeJournalPaths.insert(path)
        refreshJournalBusy()
        Task.detached(priority: .utility) { [weak self] in
            let result = AppModel.performJournalSync(request)
            guard let self else { return }
            await self.completeJournalSync(request, result: result)
        }
    }

    private func completeJournalSync(_ request: JournalSyncRequest, result: JournalSyncResult) {
        activeJournalPaths.remove(request.path)
        defer {
            startQueuedJournalSync(for: request.path)
            refreshJournalBusy()
        }

        guard isCurrentJournalRequest(request) else { return }

        switch result {
        case let .success(journalSessions):
            let cacheChanged = mergeJournalSessions(journalSessions)
            var shouldPersist = cacheChanged
            if request.adoptsPath {
                preferences.journalPath = request.path
                pendingJournalPath = nil
                shouldPersist = true
                journalPathWaiters.removeValue(forKey: request.pathIntent)?.resume(returning: true)
            }
            journalError = nil
            if shouldPersist { persist() }

            // A session may have completed while the worker held an older snapshot.
            // Queue the newest cache without overlapping work on this path.
            if journalSessionRevision != request.sessionRevision {
                synchronizeJournal()
            }

        case let .failure(message):
            if request.adoptsPath {
                pendingJournalPath = nil
                journalPathWaiters.removeValue(forKey: request.pathIntent)?.resume(returning: false)
            }
            journalError = "Markdown could not be updated. Your session is retained locally; reopen Still or save the path again to retry. \(message)"
        }
    }

    private func isCurrentJournalRequest(_ request: JournalSyncRequest) -> Bool {
        request.pathIntent == journalPathIntent && request.path == currentJournalTargetPath
    }

    private func mergeJournalSessions(_ journalSessions: [FocusSession]) -> Bool {
        let merged = Self.mergedSessions(sessions, journalSessions)
        guard merged.count != sessions.count else { return false }
        sessions = merged
        return true
    }

    private func refreshJournalBusy() {
        let target = currentJournalTargetPath
        journalIsBusy = !target.isEmpty && (activeJournalPaths.contains(target) || queuedJournalRequests[target] != nil)
    }

    private nonisolated static func performJournalSync(_ request: JournalSyncRequest) -> JournalSyncResult {
        let url = URL(fileURLWithPath: request.path)
        do {
            let exists = FileManager.default.fileExists(atPath: url.path)
            let existing = exists ? try MarkdownJournal.read(from: url) : []
            let merged = mergedSessions(request.sessions, existing)
            if exists || !merged.isEmpty || request.createsIfMissing {
                try MarkdownJournal.synchronize(sessions: merged, to: url)
            }
            return .success(merged)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private nonisolated static func mergedSessions(_ first: [FocusSession], _ second: [FocusSession]) -> [FocusSession] {
        var ids = Set<UUID>()
        let merged = (first + second).filter { ids.insert($0.id).inserted }
        return merged.sorted {
            if $0.completedAt == $1.completedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.completedAt < $1.completedAt
        }
    }

    func openJournal() {
        guard !preferences.journalPath.isEmpty else { return }
        let path = preferences.journalPath
        Task { @MainActor [weak self] in
            guard let self, await self.setJournalPathAsync(path) else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: self.preferences.journalPath))
        }
    }
    func showJournalInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: preferences.journalPath)])
    }
    func playChime() {
        guard let url = Bundle.main.url(forResource: "StillChime", withExtension: "aiff") else { return }
        sound?.stop()
        sound = NSSound(contentsOf: url, byReference: false)
        sound?.volume = 0.65
        sound?.play()
    }
    func enableNotifications() {
        Task {
            do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            catch { notificationStatus = "Unavailable: \(error.localizedDescription)" }
            await refreshNotificationStatus()
            syncNotification(requestPermission: false)
        }
    }
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        hasNotificationPermission = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notificationStatus = "Allowed"
        case .denied: notificationStatus = "Off in System Settings"
        case .notDetermined: notificationStatus = "Not requested"
        @unknown default: notificationStatus = "Unavailable"
        }
    }
    private func syncNotification(requestPermission: Bool) {
        guard !isPreview else { return }
        systemChimeScheduled = false
        notificationGeneration += 1
        let generation = notificationGeneration
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard preferences.notificationsEnabled, timer.phase == .running, let deadline = timer.deadline else { return }
        let mode = timer.mode
        let soundEnabled = preferences.soundEnabled
        Task {
            if requestPermission {
                do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
                catch { notificationStatus = "Unavailable: \(error.localizedDescription)" }
            }
            await refreshNotificationStatus()
            guard generation == notificationGeneration, hasNotificationPermission, deadline > Date() else { return }
            let content = UNMutableNotificationContent()
            content.title = mode == .focus ? "A moment, well spent." : "Ready for a fresh start?"
            content.body = mode == .focus ? "Your focus session is complete. Take a slow breath and a little break." : "Your break is over. Come back to one thing that matters."
            if soundEnabled { content.sound = UNNotificationSound(named: UNNotificationSoundName("StillChime.aiff")) }
            let id = "still.timer.\(generation).\(UUID().uuidString)"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                if generation != notificationGeneration { center.removePendingNotificationRequests(withIdentifiers: [id]) }
                else { systemChimeScheduled = soundEnabled }
            } catch { notificationStatus = "Could not schedule: \(error.localizedDescription)" }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in NotificationCenter.default.post(name: .showStill, object: nil) }
        completionHandler()
    }
    func persist() {
        guard !isPreview, canSave else { return }
        do {
            try FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let archive = LocalArchive(timer: timer, sessions: sessions, preferences: preferences)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(archive).write(to: dataURL, options: .atomic)
            storageError = nil
        } catch { storageError = "Your session could not be saved: \(error.localizedDescription)" }
    }
    private func load() {
        guard FileManager.default.fileExists(atPath: dataURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let archive = try decoder.decode(LocalArchive.self, from: Data(contentsOf: dataURL))
            timer = archive.timer
            sessions = archive.sessions
            preferences = archive.preferences
            preferences.focusMinutes = min(180, max(1, preferences.focusMinutes))
            preferences.shortBreakMinutes = min(60, max(1, preferences.shortBreakMinutes))
            preferences.longBreakMinutes = min(90, max(1, preferences.longBreakMinutes))
        } catch {
            let backup = dataURL.deletingLastPathComponent().appendingPathComponent("state-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try FileManager.default.copyItem(at: dataURL, to: backup)
                storageError = "Could not read saved data. The original is preserved as \(backup.lastPathComponent)."
            } catch {
                canSave = false
                storageError = "Could not read or back up saved data. Saving is paused to preserve the original."
            }
        }
    }
}

extension Notification.Name { static let showStill = Notification.Name("showStill") }
