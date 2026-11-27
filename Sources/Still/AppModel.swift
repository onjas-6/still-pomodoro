// Created 2026-09-15 · gpt-6-astra · Codex
import AppKit
import Combine
import StillCore
import UserNotifications

struct LocalArchive: Codable {
    var version = 3
    var timer = TimerState()
    var sessions: [FocusSession] = []
    var preferences = Preferences()
    // Optional keys keep v1/v2 recovery archives readable.
    var dailyEvents: [DailyEvent]?
    var lastPlanPromptDay: String?
    var journalPathConfirmed: Bool?
    var notes: [StillNote]?
}

private struct JournalSyncRequest: Sendable {
    let path: String
    let pathIntent: Int
    let entries: JournalEntries
    let importsLegacyJournal: Bool
    let adoptsPath: Bool
    let createsIfMissing: Bool
}

private enum JournalSyncResult: Sendable {
    case success(JournalEntries)
    case failure(String)
}

@MainActor
final class AppModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var timer = TimerState()
    private var entries = JournalEntries() {
        didSet { days = FocusDay.history(entries) }
    }
    @Published private(set) var days: [String: FocusDay] = [:]
    private(set) var todayID = DailyEvent.dayID(for: Date())
    private var lastPlanPromptDay: String?
    private var journalPathConfirmed = false
    var sessions: [FocusSession] { entries.sessions }
    var notes: [StillNote] { entries.notes }
    @Published var preferences = Preferences()
    @Published private(set) var now = Date() {
        didSet {
            todayID = DailyEvent.dayID(for: now)
        }
    }
    @Published private(set) var restReminderActive = false
    /// A live focus completion needs a visual path even when notifications or sound are off.
    /// This is deliberately transient: restored, already-expired timers do not re-present it.
    @Published private(set) var focusCompletionAlertActive = false
    @Published var storageError: String?
    @Published var notificationStatus = "Not requested"
    @Published private(set) var bedtimeNotificationStatus = "Checking daily notification…"
    @Published var journalError: String?
    @Published private(set) var journalIsBusy = false
    var onWindowPreferencesChanged: (() -> Void)?
    private var pulse: AnyCancellable?
    let playTone: (AlertTone) -> Void
    private var notificationGeneration = 0
    private var restNotificationGeneration = 0
    private var hasNotificationPermission = false
    private var systemChimeScheduled = false
    private var restSnoozedUntil: Date?
    private var lastRestCheckSecond: Int?
    private var canSave = true
    private var journalPathIntent = 0
    private var pendingJournalPath: String?
    private var queuedJournalRequests: [String: JournalSyncRequest] = [:]
    private var activeJournalPaths: Set<String> = []
    private var journalPathWaiters: [Int: CheckedContinuation<Bool, Never>] = [:]
    let dataURL: URL
    let isPreview: Bool
    private let managesSystemNotifications: Bool
    let inspiration: InspirationStore
    let stayAwake: StayAwake

    init(dataDirectory: URL? = nil, preview: Bool = false, syncJournalOnLaunch: Bool = true,
         playTone: @escaping (AlertTone) -> Void = AlertTonePlayer().play) {
        self.playTone = playTone
        isPreview = preview
        managesSystemNotifications = !preview && dataDirectory == nil
        dataURL = (dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Still", isDirectory: true)).appendingPathComponent("state.json")
        inspiration = InspirationStore(directory: dataURL.deletingLastPathComponent(), preview: preview)
        stayAwake = StayAwake(directory: dataURL.deletingLastPathComponent(), enabled: !preview && dataDirectory == nil)
        super.init()
        if !preview { load() }
        if let dataDirectory {
            if preferences.journalPath.isEmpty {
                preferences.journalPath = dataDirectory.appendingPathComponent("Still-sessions.md").path
            }
        } else if preferences.journalPath.isEmpty ||
                    (!journalPathConfirmed && preferences.journalPath == JournalLocation.legacyJournal.path) {
            let hasMySpace = !preview && FileManager.default.fileExists(atPath: JournalLocation.mySpace.path)
            preferences.journalPath = (hasMySpace ? JournalLocation.mySpaceJournal : JournalLocation.legacyJournal).path
        }
        UNUserNotificationCenter.current().delegate = self
        // Reconcile a deadline that elapsed while Still was closed, without replaying an old chime.
        let restoringRunningTimer = timer.phase == .running
        if let session = timer.tick(at: now) { add(session) }
        if restoringRunningTimer && timer.phase == .completed { persist() }
        refreshRestReminder(to: now)
        pulse = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] date in
            self?.refreshClock(to: date)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(timeZoneChanged), name: .NSSystemTimeZoneDidChange, object: nil)
        if managesSystemNotifications {
            // Older releases used one-off timer IDs. Remove only those legacy requests;
            // the new daily rest reminder has its own stable identifier.
            let center = UNUserNotificationCenter.current()
            center.getPendingNotificationRequests { requests in
                let legacy = requests.map(\.identifier).filter { $0.hasPrefix("still.timer.") }
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: legacy)
            }
        }
        if !preview {
            // The existence check and any Markdown I/O run on the journal worker. A
            // newly generated default path with no sessions is intentionally untouched.
            if syncJournalOnLaunch { synchronizeJournal() }
            if managesSystemNotifications {
                Task { await refreshNotificationStatus() }
                if timer.phase == .running { syncNotification(requestPermission: false) }
                syncRestNotification()
            }
        }
    }

    var remaining: Int { max(0, Int(ceil(timer.remaining(at: now)))) }
    var minutes: String { String(format: "%02d", remaining / 60) }
    var seconds: String { String(format: "%02d", remaining % 60) }
    var progress: Double { min(1, max(0, 1 - timer.remaining(at: now) / timer.duration)) }
    var today: FocusDay { days[todayID] ?? FocusDay(id: todayID) }

    var suggestedGoal: Int {
        if let goal = today.goal { return goal }
        let previous = days.values.filter { $0.id < todayID && ($0.goal ?? 0) > 0 }.max { $0.id < $1.id }
        return previous?.goal ?? 2
    }

    func needsDailyGoalPrompt(at date: Date = Date()) -> Bool {
        let day = DailyEvent.dayID(for: date)
        return days[day]?.goal == nil && lastPlanPromptDay != day
    }

    func takeDailyGoalPrompt(at date: Date = Date()) -> Bool {
        guard needsDailyGoalPrompt(at: date) else { return false }
        let day = DailyEvent.dayID(for: date)
        lastPlanPromptDay = day
        persist()
        return true
    }

    func setDailyGoal(_ count: Int, at date: Date = Date()) {
        guard DailyEvent.goalRange.contains(count) else { return }
        advance(to: date)
        guard today.goal != count else { return }
        entries.events.append(DailyEvent(.goal(count), at: date))
        persist()
        synchronizeJournal()
    }
    var totalMinutes: Int { Int(sessions.reduce(0) { $0 + $1.duration } / 60) }
    var isInProgress: Bool { timer.phase == .running || timer.phase == .paused }
    private var suggestedBreakMode: TimerMode { today.completed % 4 == 0 ? .longBreak : .shortBreak }
    var focusCompletionBreakButtonTitle: String {
        let minutes = Int(duration(for: suggestedBreakMode) / 60)
        return "Start \(minutes)-minute break"
    }
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
        case .ready, .paused:
            focusCompletionAlertActive = false
            timer.start(at: now)
        case .completed:
            focusCompletionAlertActive = false
            let next: TimerMode = timer.mode == .focus ? suggestedBreakMode : .focus
            timer.configure(mode: next, duration: duration(for: next))
            timer.start(at: now)
        }
        persist()
        syncNotification(requestPermission: timer.phase == .running)
    }
    func startFocus(minutes: Int) {
        guard !isInProgress else { return }
        now = Date()
        focusCompletionAlertActive = false
        timer.configure(mode: .focus, duration: Double(min(180, max(1, minutes)) * 60))
        timer.start(at: now)
        persist()
        syncNotification(requestPermission: true)
    }
    func startBreak(_ mode: TimerMode) {
        guard !isInProgress, mode != .focus else { return }
        now = Date()
        focusCompletionAlertActive = false
        timer.configure(mode: mode, duration: duration(for: mode))
        timer.start(at: now)
        persist()
        syncNotification(requestPermission: true)
    }
    func selectMode(_ mode: TimerMode) {
        guard !isInProgress else { return }
        focusCompletionAlertActive = false
        timer.configure(mode: mode, duration: duration(for: mode))
        now = Date()
        persist()
        syncNotification(requestPermission: false)
    }
    func reset() {
        advance(to: Date())
        let stopped = isInProgress && timer.mode == .focus
        if stopped, let id = timer.sessionID, let start = timer.startedAt {
            entries.events.append(DailyEvent(.stopped(startedAt: start), at: now, id: id))
        }
        focusCompletionAlertActive = false
        timer.configure(mode: timer.mode, duration: duration(for: timer.mode))
        persist()
        if stopped { synchronizeJournal() }
        syncNotification(requestPermission: false)
    }
    /// - Parameter minutes: nil keeps the Mac awake until turned off.
    func startStayAwake(minutes: Int?) {
        stayAwake.start(minutes: minutes, lidClosed: preferences.stayAwakeLidClosed)
    }
    /// Saves the lid-closed choice and applies it to a running session, keeping its end time.
    func setStayAwakeLidClosed(_ enabled: Bool) {
        preferences.stayAwakeLidClosed = enabled
        savePreferences()
        guard let until = stayAwake.until else { return }
        startStayAwake(minutes: until == .distantFuture ? nil : max(1, Int((until.timeIntervalSinceNow / 60).rounded())))
    }
    func savePreferences() {
        preferences.sanitize()
        if timer.phase == .ready { timer.configure(mode: timer.mode, duration: duration(for: timer.mode)) }
        persist()
        onWindowPreferencesChanged?()
        syncNotification(requestPermission: false)
        refreshRestReminder(to: Date())
        syncRestNotification()
    }
    func advance(to date: Date) {
        now = date
        let wasRunning = timer.phase == .running
        // Calling a mutating method through @Published also publishes no-op ticks.
        // Work on a value copy, publishing only a real phase transition.
        var updated = timer
        let session = updated.tick(at: date)
        if updated.phase != timer.phase || session != nil { timer = updated }
        if let session { add(session); persist(); synchronizeJournal() }
        if wasRunning && timer.phase == .completed {
            persist()
            // Always give a just-finished focus session a local visual acknowledgement.
            // It is intentionally independent of sound/notification settings so it also
            // covers muted Macs and denied notification permission.
            if timer.mode == .focus {
                focusCompletionAlertActive = true
                // Focus timer notifications stay silent while Still is running, so
                // this bundled chime is the one audible completion signal.
                if shouldPlayDirectChime(for: .focus) { playTone(preferences.timerTone) }
            } else if preferences.soundEnabled && !systemChimeScheduled {
                // Preserve the existing break behavior when its notification was not
                // scheduled (for example, notifications are unavailable).
                playTone(preferences.timerTone)
            }
        }
    }

    func dismissFocusCompletionAlert() {
        focusCompletionAlertActive = false
    }

    /// The live focus sound must not depend on notification sounds being allowed.
    /// Internal so the timer self-check can cover the decision without playing audio.
    func shouldPlayDirectChime(for completedMode: TimerMode) -> Bool {
        completedMode == .focus && preferences.soundEnabled
    }
    func refreshClock(to date: Date) {
        let second = Int(date.timeIntervalSince1970)
        if lastRestCheckSecond != second {
            lastRestCheckSecond = second
            refreshRestReminder(to: date)
        }
        // Keep the 250 ms deadline check, but invalidate the UI only when a shown
        // second changes. Paused/ready/completed clocks only refresh at midnight.
        let displayed = max(0, Int(ceil(timer.remaining(at: date))))
        if (timer.phase == .running && displayed != remaining)
            || !Calendar.current.isDate(date, inSameDayAs: now) {
            advance(to: date)
        }
    }
    @objc private func timeZoneChanged() {
        days = FocusDay.history(entries)
        woke()
    }

    @objc private func woke() {
        let date = Date()
        advance(to: date)
        refreshRestReminder(to: date)
    }
    func snoozeRestReminder(at date: Date = Date()) {
        restSnoozedUntil = date.addingTimeInterval(5 * 60)
        refreshRestReminder(to: date)
    }
    private func refreshRestReminder(to date: Date) {
        let inWindow = preferences.restReminderEnabled && RestSchedule.contains(
            date, startMinute: preferences.restStartMinute, endMinute: preferences.restEndMinute)
        let shouldShow = inWindow && (restSnoozedUntil.map { date >= $0 } ?? true)
        if restReminderActive != shouldShow { restReminderActive = shouldShow }
        if !inWindow { restSnoozedUntil = nil }
    }
    /// Records a note in the local cache and the Markdown journal. Preview models never write.
    func addNote(_ note: StillNote) {
        guard !isPreview, !entries.notes.contains(where: { $0.id == note.id }) else { return }
        entries.notes.append(note)
        persist()
        synchronizeJournal()
    }

    private func add(_ session: FocusSession) {
        if !sessions.contains(where: { $0.id == session.id }) {
            entries.sessions.append(session)
        }
    }
    var journalDisplayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return preferences.journalPath.hasPrefix(home + "/") ? "~" + preferences.journalPath.dropFirst(home.count) : preferences.journalPath
    }
    private func importsLegacyJournal(for path: String) -> Bool {
        !journalPathConfirmed && path == preferences.journalPath && path == JournalLocation.mySpaceJournal.path
    }

    @discardableResult
    func setJournalPath(_ path: String) -> Bool {
        guard !isPreview else { preferences.journalPath = path; return true }
        guard let normalizedPath = normalizedJournalPath(path) else { return false }
        let intent = beginJournalPathChange(to: normalizedPath)
        let request = JournalSyncRequest(path: normalizedPath, pathIntent: intent, entries: entries,
            importsLegacyJournal: importsLegacyJournal(for: normalizedPath), adoptsPath: true, createsIfMissing: true)
        switch Self.performJournalSync(request) {
        case let .success(records):
            _ = importEntries(records)
            preferences.journalPath = normalizedPath
            journalPathConfirmed = true
            pendingJournalPath = nil
            journalError = nil
            persist()
            refreshJournalBusy()
            return true
        case let .failure(message):
            pendingJournalPath = nil
            journalError = "Could not use this Markdown file: \(message)"
            refreshJournalBusy()
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

    func synchronizeJournal() {
        guard !isPreview else { return }
        let path = pendingJournalPath ?? preferences.journalPath
        guard !path.isEmpty else { return }
        enqueueJournalSync(
            path: path,
            intent: journalPathIntent,
            adoptsPath: pendingJournalPath == path,
            createsIfMissing: !entries.isEmpty || pendingJournalPath == path
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
            entries: entries,
            importsLegacyJournal: importsLegacyJournal(for: path),
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
        case let .success(records):
            var shouldPersist = importEntries(records)
            if request.adoptsPath || request.importsLegacyJournal {
                journalPathConfirmed = true
                shouldPersist = true
            }
            if request.adoptsPath {
                preferences.journalPath = request.path
                pendingJournalPath = nil
                journalPathWaiters.removeValue(forKey: request.pathIntent)?.resume(returning: true)
            }
            journalError = nil
            if shouldPersist { persist() }

        case let .failure(message):
            if request.adoptsPath {
                pendingJournalPath = nil
                journalPathWaiters.removeValue(forKey: request.pathIntent)?.resume(returning: false)
            }
            journalError = "Markdown could not be updated. Your records are cached locally. Reopen Daily Overview to retry. \(message)"
        }
    }

    private func isCurrentJournalRequest(_ request: JournalSyncRequest) -> Bool {
        request.pathIntent == journalPathIntent && request.path == currentJournalTargetPath
    }

    private func importEntries(_ journal: JournalEntries) -> Bool {
        let missing = journal.missing(from: entries)
        guard !missing.isEmpty else { return false }
        entries.append(missing)
        return true
    }

    private func refreshJournalBusy() {
        let target = currentJournalTargetPath
        journalIsBusy = !target.isEmpty && (activeJournalPaths.contains(target) || queuedJournalRequests[target] != nil)
    }

    private nonisolated static func performJournalSync(_ request: JournalSyncRequest) -> JournalSyncResult {
        do {
            let url = try JournalLocation.resolved(URL(fileURLWithPath: request.path))
            var records = request.entries
            if request.importsLegacyJournal, FileManager.default.fileExists(atPath: JournalLocation.legacyJournal.path) {
                let old = try MarkdownJournal.readEntries(from: JournalLocation.legacyJournal)
                records.append(old.missing(from: records))
            }
            if records.isEmpty && !request.createsIfMissing && !FileManager.default.fileExists(atPath: url.path) {
                return .success(records)
            }
            return .success(try MarkdownJournal.synchronize(records, to: url))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func openJournal() {
        guard !preferences.journalPath.isEmpty else { return }
        let path = preferences.journalPath
        Task { @MainActor [weak self] in
            guard let self, await self.setJournalPathAsync(path) else { return }
            if let url = try? JournalLocation.resolved(URL(fileURLWithPath: self.preferences.journalPath)) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    func showJournalInFinder() {
        if let url = try? JournalLocation.resolved(URL(fileURLWithPath: preferences.journalPath)) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    func enableNotifications() {
        Task {
            do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            catch { notificationStatus = "Unavailable: \(error.localizedDescription)" }
            await refreshNotificationStatus()
            syncNotification(requestPermission: false)
            syncRestNotification()
        }
    }
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        hasNotificationPermission = false
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            hasNotificationPermission = true
            notificationStatus = settings.alertSetting == .enabled && settings.alertStyle != .none
                ? "Allowed" : "Banners off in System Settings"
        case .denied: notificationStatus = "Off in System Settings"
        case .notDetermined: notificationStatus = "Not requested"
        @unknown default: notificationStatus = "Unavailable"
        }
    }
    private func syncNotification(requestPermission: Bool) {
        guard managesSystemNotifications else { return }
        systemChimeScheduled = false
        notificationGeneration += 1
        let generation = notificationGeneration
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["still.timer"])
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
            // A running focus timer plays the selected tone itself at the live
            // transition. Leave its notification silent to prevent two chimes.
            // Breaks retain their existing system-notification sound behavior.
            let usesSystemChime = soundEnabled && mode != .focus
            if usesSystemChime { content.sound = preferences.timerTone.notificationSound }
            let id = "still.timer"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                if generation == notificationGeneration { systemChimeScheduled = usesSystemChime }
            } catch { notificationStatus = "Could not schedule: \(error.localizedDescription)" }
        }
    }
    /// A focus notification is intentionally silent while Still is alive to avoid
    /// duplicating the direct chime. On a normal quit, replace it with an audible
    /// fallback and wait only briefly for the notification service to accept it.
    func prepareNotificationForTermination() {
        guard managesSystemNotifications,
              preferences.notificationsEnabled,
              preferences.soundEnabled,
              timer.phase == .running,
              timer.mode == .focus,
              let deadline = timer.deadline,
              deadline > Date() else { return }

        notificationGeneration += 1
        let content = UNMutableNotificationContent()
        content.title = "A moment, well spent."
        content.body = "Your focus session is complete. Take a slow breath and a little break."
        content.sound = preferences.timerTone.notificationSound
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: "still.timer", content: content, trigger: trigger)
        let accepted = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error { Task { @MainActor in self?.notificationStatus = "Could not schedule: \(error.localizedDescription)" } }
            accepted.signal()
        }
        _ = accepted.wait(timeout: .now() + 0.35)
    }
    func syncRestNotification() {
        guard managesSystemNotifications else { return }
        restNotificationGeneration += 1
        let generation = restNotificationGeneration
        let center = UNUserNotificationCenter.current()
        guard let request = RestSchedule.notificationRequest(for: preferences) else {
            center.removePendingNotificationRequests(withIdentifiers: [RestSchedule.notificationID])
            return
        }
        Task {
            await refreshNotificationStatus()
            guard generation == restNotificationGeneration else { return }
            guard hasNotificationPermission else {
                bedtimeNotificationStatus = "Daily notification: " + notificationStatus
                return
            }
            let pending = await center.pendingNotificationRequests()
            guard generation == restNotificationGeneration else { return }
            let existing = pending.first { $0.identifier == request.identifier }
            do {
                if existing?.trigger != request.trigger || existing?.content.body != request.content.body {
                    // Adding the same identifier replaces the previous bedtime without a gap.
                    try await center.add(request)
                }
                guard generation == restNotificationGeneration else { return }
                bedtimeNotificationStatus = notificationStatus == "Allowed"
                    ? "Daily notification scheduled." : "Daily notification scheduled. Banners are off."
            } catch {
                guard generation == restNotificationGeneration else { return }
                bedtimeNotificationStatus = "Could not schedule daily notification: \(error.localizedDescription)"
            }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        var options: UNNotificationPresentationOptions = [.banner]
        if notification.request.content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in NotificationCenter.default.post(name: .showStill, object: nil) }
        completionHandler()
    }
    func persist() {
        guard !isPreview, canSave else { return }
        do {
            try FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let archive = LocalArchive(timer: timer, sessions: sessions, preferences: preferences,
                dailyEvents: entries.events, lastPlanPromptDay: lastPlanPromptDay, journalPathConfirmed: journalPathConfirmed,
                notes: entries.notes)
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
            entries = JournalEntries(sessions: archive.sessions, events: archive.dailyEvents ?? [], notes: archive.notes ?? [])
            lastPlanPromptDay = archive.lastPlanPromptDay
            journalPathConfirmed = archive.journalPathConfirmed ?? false
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
