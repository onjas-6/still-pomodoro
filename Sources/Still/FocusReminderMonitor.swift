import AppKit
import Combine
import StillCore

enum FocusNotice: Equatable {
    case distraction(String)
    case browserAccess
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

@MainActor
final class FocusReminderMonitor {
    private weak var model: AppModel?
    private var configuration: AnyCancellable?
    private var activation: AnyCancellable?
    private var browserTask: Task<Void, Never>?
    private var snoozeTask: Task<Void, Never>?
    private var session: UUID?
    private var visit = FocusVisit()
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
         sleepForSnooze: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.model = model
        self.frontmost = frontmost
        self.readSite = readSite
        self.sleepForSnooze = sleepForSnooze
        presenter = FocusNoticePanel()
        presenter.dismiss = { [weak self] in self?.dismiss() }
        presenter.snooze = { [weak self] duration in self?.snooze(for: duration) }
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
        if snoozeTask == nil { startObserving() }
    }

    private func stopObserving() {
        activation?.cancel()
        activation = nil
        resetVisit()
    }

    private func startObserving() {
        guard session != nil, !targets.apps.isEmpty || !targets.websites.isEmpty else { return }
        activation = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.foregroundChanged() }
        foregroundChanged()
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
        let previous = visit.visible
        visit.enter(notice)
        if previous != visit.visible { presenter.present(visit.visible) }
    }

    func snooze(for duration: Duration) {
        guard case .distraction = visit.visible else { return }
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
        visit.dismiss()
        presenter.present(nil)
    }
}
