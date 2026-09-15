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

@MainActor
final class AppModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var timer = TimerState()
    @Published private(set) var sessions: [FocusSession] = []
    @Published var preferences = Preferences()
    @Published private(set) var now = Date()
    @Published var storageError: String?
    @Published var notificationStatus = "Not requested"
    @Published var journalError: String?
    var onWindowPreferencesChanged: (() -> Void)?
    private var pulse: AnyCancellable?
    private var sound: NSSound?
    private var notificationGeneration = 0
    private var hasNotificationPermission = false
    private var systemChimeScheduled = false
    private var canSave = true
    let dataURL: URL
    let isPreview: Bool

    init(dataDirectory: URL? = nil, preview: Bool = false) {
        isPreview = preview
        dataURL = (dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Still", isDirectory: true)).appendingPathComponent("state.json")
        super.init()
        if !preview { load() }
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
            if !sessions.isEmpty || FileManager.default.fileExists(atPath: preferences.journalPath) { synchronizeJournal() }
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
        if !sessions.contains(where: { $0.id == session.id }) { sessions.append(session) }
    }
    var journalDisplayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return preferences.journalPath.hasPrefix(home + "/") ? "~" + preferences.journalPath.dropFirst(home.count) : preferences.journalPath
    }
    @discardableResult
    func setJournalPath(_ path: String) -> Bool {
        guard !isPreview else { preferences.journalPath = path; return true }
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), !expanded.isEmpty else {
            journalError = "Choose an absolute path ending in .md."
            return false
        }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        do {
            let existing = FileManager.default.fileExists(atPath: url.path) ? try MarkdownJournal.read(from: url) : []
            var merged = sessions
            var ids = Set(merged.map(\.id))
            merged.append(contentsOf: existing.filter { ids.insert($0.id).inserted })
            merged.sort { $0.completedAt < $1.completedAt }
            try MarkdownJournal.synchronize(sessions: merged, to: url)
            sessions = merged
            preferences.journalPath = url.path
            journalError = nil
            persist()
            return true
        } catch {
            journalError = "Could not use this Markdown file: \(error.localizedDescription)"
            return false
        }
    }
    private func synchronizeJournal() {
        guard !isPreview, !preferences.journalPath.isEmpty else { return }
        do {
            let url = URL(fileURLWithPath: preferences.journalPath)
            if FileManager.default.fileExists(atPath: url.path) {
                let existing = try MarkdownJournal.read(from: url)
                var ids = Set(sessions.map(\.id))
                let imported = existing.filter { ids.insert($0.id).inserted }
                if !imported.isEmpty {
                    sessions.append(contentsOf: imported)
                    sessions.sort { $0.completedAt < $1.completedAt }
                    persist()
                }
            }
            try MarkdownJournal.synchronize(sessions: sessions, to: url)
            journalError = nil
        } catch {
            journalError = "Markdown could not be updated. Your session is retained locally; reopen Still or save the path again to retry. \(error.localizedDescription)"
        }
    }
    func openJournal() {
        if !FileManager.default.fileExists(atPath: preferences.journalPath) {
            guard setJournalPath(preferences.journalPath) else { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: preferences.journalPath))
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
