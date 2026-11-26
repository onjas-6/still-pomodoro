import AppKit
import Combine
import StillCore

enum FocusNotice: Equatable {
    case distraction(String)
    case browserAccess
    case inactive(minutes: Int)
}

/// Keep a dismissal scoped to the current visit. Moving to an allowed destination
/// (or ending focus) rearms the reminder even if the next visit is to the same site.
struct FocusVisit {
    private(set) var notice: FocusNotice?
    private(set) var dismissed = false

    mutating func enter(_ next: FocusNotice?) {
        if next != notice { notice = next; dismissed = false }
    }

    var visible: FocusNotice? { dismissed ? nil : notice }
    mutating func dismiss() { dismissed = true }
}

struct ForegroundApp {
    let pid: pid_t
    let bundleID: String

    static func current() -> Self? {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return nil }
        return Self(pid: app.processIdentifier, bundleID: id)
    }
}

struct InactivityEnvironment {
    var idleSeconds: () -> TimeInterval = FocusInactivity.inputIdleSeconds
    var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var desktopAvailable: () -> Bool = {
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool != true
    }
    var playSound: () -> Void = {
        if NSSound(named: "Tink")?.play() != true { NSSound.beep() }
    }
}

@MainActor
final class FocusReminderMonitor {
    private weak var model: AppModel?
    private var configuration: AnyCancellable?
    private var activation: AnyCancellable?
    private var browserTask: Task<Void, Never>?
    private var snoozeTask: Task<Void, Never>?
    private var session: UUID?
    private var visit = FocusVisit()
    private enum CheckIn { case armed, visible, acknowledged }
    private var checkIn = CheckIn.armed
    private var activityReturnedAt: TimeInterval?
    private var presented: FocusNotice?
    private var idleSignal = FocusInactivity()
    private var idleTicks: AnyCancellable?
    private var desktopChanges: AnyCancellable?
    private var screenLocked = false
    private let inactivity: InactivityEnvironment
    private var targets = FocusTargets()
    private var pid: pid_t?
    private var offeredAccess = false
    private let frontmost: () -> ForegroundApp?
    private let readSite: @Sendable (pid_t) -> BrowserLocation.Result
    private let sleepForSnooze: @Sendable (Duration) async throws -> Void
    private let presenter: FocusNoticePanel
    private let accessOfferKey = "didOfferWebsiteReminders"

    init(model: AppModel, store: FocusTargetStore,
         frontmost: @escaping () -> ForegroundApp? = { ForegroundApp.current() },
         readSite: @escaping @Sendable (pid_t) -> BrowserLocation.Result = { BrowserLocation.read(pid: $0) },
         sleepForSnooze: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         inactivity: InactivityEnvironment = InactivityEnvironment()) {
        self.inactivity = inactivity
        self.model = model
        self.frontmost = frontmost
        self.readSite = readSite
        self.sleepForSnooze = sleepForSnooze
        presenter = FocusNoticePanel()
        presenter.dismiss = { [weak self] in self?.dismiss() }
        presenter.snooze = { [weak self] duration in self?.snooze(for: duration) }
        let workspace = NSWorkspace.shared.notificationCenter
        let desktopEvents = [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                             NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
                             NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification]
            .map { workspace.publisher(for: $0).eraseToAnyPublisher() }
        let locked = Notification.Name("com.apple.screenIsLocked")
        let unlocked = Notification.Name("com.apple.screenIsUnlocked")
        let lockEvents = [locked, unlocked].map {
            DistributedNotificationCenter.default().publisher(for: $0).eraseToAnyPublisher()
        }
        desktopChanges = Publishers.MergeMany(desktopEvents + lockEvents).receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self else { return }
                if note.name == locked { self.screenLocked = true }
                if note.name == unlocked { self.screenLocked = false }
                self.resetInactivity()
            }
        configuration = model.$timer.map { timer in
            timer.mode == .focus && timer.phase == .running ? timer.sessionID : nil
        }.removeDuplicates()
            .combineLatest(store.$targets.removeDuplicates())
            .sink { [weak self] session, targets in
                self?.configure(session: targets.enabled ? session : nil, targets: targets)
            }
    }

    deinit {
        browserTask?.cancel()
        snoozeTask?.cancel()
    }

    private func configure(session: UUID?, targets: FocusTargets) {
        if self.session != session {
            snoozeTask?.cancel()
            snoozeTask = nil
        }
        self.session = session
        self.targets = targets
        stopObserving()
        resetInactivity()
        if snoozeTask == nil { startObserving() }
    }

    private func stopObserving() {
        idleTicks = nil
        checkIn = .armed
        activityReturnedAt = nil
        activation?.cancel()
        activation = nil
        resetVisit()
    }

    private func startObserving() {
        guard session != nil else { return }
        if targets.idleMinutes > 0 {
            idleTicks = model?.$now.dropFirst().sink { [weak self] date in self?.checkInIfIdle(at: date) }
        }
        guard !targets.apps.isEmpty || !targets.websites.isEmpty else { return }
        activation = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.foregroundChanged() }
        foregroundChanged()
    }

    private func resetInactivity() {
        idleSignal.reset(at: inactivity.uptime())
        checkIn = .armed
        activityReturnedAt = nil
        updatePanel()
    }

    private func checkInIfIdle(at date: Date) {
        guard !screenLocked, let model, let deadline = model.timer.deadline, date < deadline else { return }
        let now = inactivity.uptime()
        let due = idleSignal.evaluate(idleSeconds: inactivity.idleSeconds(), at: now,
                                      threshold: TimeInterval(targets.idleMinutes * 60))
        if due {
            activityReturnedAt = nil
            guard checkIn == .armed else { return }
            guard inactivity.desktopAvailable() else { resetInactivity(); return }
            checkIn = .visible
            updatePanel()
            if model.preferences.soundEnabled { inactivity.playSound() }
        } else if checkIn == .visible {
            // Give someone reaching for the acknowledgement or snooze buttons time to click.
            let returned = activityReturnedAt ?? now
            activityReturnedAt = returned
            if now - returned >= 5 {
                checkIn = .armed
                activityReturnedAt = nil
                updatePanel()
            }
        } else {
            checkIn = .armed
        }
    }

    private func resetVisit() {
        browserTask?.cancel()
        browserTask = nil
        pid = nil
        offeredAccess = false
        show(nil)
    }

    private func foregroundChanged() {
        let app = frontmost()
        guard app?.pid != pid else { return }
        resetVisit()
        guard let app else { return }
        let bundle = app.bundleID.lowercased()
        let process = app.pid
        pid = process
        if let target = targets.apps.first(where: { $0.id.lowercased() == bundle }) {
            show(.distraction(target.name))
        } else if BrowserLocation.browsers.contains(bundle), !targets.websites.isEmpty {
            let readSite = self.readSite
            browserTask = Task { [weak self] in
                while !Task.isCancelled {
                    let result = await Task.detached(priority: .utility) { readSite(process) }.value
                    guard !Task.isCancelled, let self else { return }
                    if self.frontmost()?.pid == process {
                        switch result {
                        case let .site(host): self.observed(host: host)
                        case .accessRequired: self.offerAccessIfNeeded()
                        }
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func observed(host: String?) {
        show(host.flatMap(targets.matchedDomain).map(FocusNotice.distraction))
    }

    private func offerAccessIfNeeded() {
        if !offeredAccess && !UserDefaults.standard.bool(forKey: accessOfferKey) {
            offeredAccess = true
            UserDefaults.standard.set(true, forKey: accessOfferKey)
        }
        show(offeredAccess ? .browserAccess : nil)
    }

    private func show(_ notice: FocusNotice?) {
        visit.enter(notice)
        updatePanel()
    }

    private func updatePanel() {
        let next: FocusNotice? = checkIn == .visible ? .inactive(minutes: targets.idleMinutes) : visit.visible
        guard next != presented else { return }
        presented = next
        presenter.present(next)
    }

    func snooze(for duration: Duration) {
        switch presented {
        case .distraction, .inactive: break
        case .browserAccess, nil: return
        }
        stopObserving()
        let sleep = sleepForSnooze
        snoozeTask = Task { [weak self] in
            do { try await sleep(duration) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.snoozeTask = nil
            // The Mac can wake after both deadlines, before the timer's next tick.
            guard let deadline = self.model?.timer.deadline, deadline > Date() else { return }
            self.startObserving()
        }
    }

    private func dismiss() {
        if checkIn == .visible {
            checkIn = .acknowledged
            activityReturnedAt = nil
        } else {
            visit.dismiss()
        }
        updatePanel()
    }
}
