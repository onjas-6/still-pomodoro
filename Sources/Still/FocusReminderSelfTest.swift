import AppKit

/// Drives the native reminder windows with an isolated timer and simulated
/// foreground changes. Never reads the user's browser, rules, or timer archive.
@MainActor
enum FocusReminderSelfTest {
    static func run(model: AppModel) async -> Int32 {
        precondition(model.isPreview)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Still-FocusTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FocusTargetStore(directory: directory)
        let game = ForegroundApp(pid: 1, bundleID: "com.example.Game")
        let browser = ForegroundApp(pid: 2, bundleID: "com.google.Chrome")
        var frontmost = game
        let site = TestSite()
        let clock = SnoozeClock()
        let monitor = FocusReminderMonitor(model: model, store: store, frontmost: { frontmost },
                                          readSite: { _ in .site(site.read()) },
                                          sleepForSnooze: { await clock.sleep(for: $0) })
        defer { withExtendedLifetime(monitor) {} }
        var failures = [String]()

        func check(_ condition: Bool, _ label: String) {
            if !condition { failures.append(label) }
        }
        func visible(_ title: String) -> Bool {
            NSApp.windows.contains { $0.title == title && $0.isVisible && $0.frame.height > 50 }
        }
        let nudge = "Still — Focus reminder"
        let completion = "Still — Focus complete"
        model.preferences.soundEnabled = false
        model.preferences.notificationsEnabled = false
        model.reset()
        store.update {
            $0.apps = [FocusApp(id: game.bundleID, name: "Example Game")]
            $0.websites = ["example.org"]
        }
        check(FocusTargetStore(directory: directory).targets == store.targets, "Saved rules round-trip")
        check(FocusTargets.domain(" HTTPS://WWW.Example.ORG.:443/watch?q=1#x ") == "example.org", "Pasted URL normalization")
        check(FocusTargets.domain("file:///tmp/example.org") == nil && FocusTargets.domain("bad host") == nil,
              "Non-web input rejected")
        check(store.targets.matchedDomain("studio.example.org") == nil && store.targets.matchedDomain("example.org.evil.com") == nil,
              "Work subdomains and lookalikes excluded")
        check(!visible(nudge), "Ready timer hides reminder")
        model.startFocus(minutes: 1)
        check(visible(nudge), "Starting focus inside a listed app raises reminder")
        let originalDeadline = model.timer.deadline
        monitor.snooze(for: .seconds(60))
        await wait { clock.duration != nil }
        check(clock.duration == .seconds(60) && !visible(nudge), "One-minute action hides the reminder for 60 seconds")
        clock.finish()
        await wait { visible(nudge) }
        check(visible(nudge) && model.timer.deadline == originalDeadline, "Expiry rechecks the same app without changing focus")
        model.primaryAction()
        check(!visible(nudge), "Pausing dismisses reminder")
        model.primaryAction()
        check(visible(nudge), "Resuming checks current app")
        store.update { $0.enabled = false }
        check(!visible(nudge), "Disabling reminders takes effect immediately")
        store.update { $0.enabled = true }
        frontmost = browser
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await wait { !visible(nudge) }
        check(!visible(nudge), "Switching to an allowed browser tab clears app reminder")
        site.set("example.org")
        await wait { visible(nudge) }
        check(visible(nudge), "Tab change raises website reminder inside same browser")
        monitor.snooze(for: .seconds(300))
        await wait { clock.duration != nil }
        check(clock.duration == .seconds(300) && !visible(nudge), "Five-minute action hides the site reminder for 300 seconds")
        frontmost = game
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        store.update { $0.websites.append("other.example.org") }
        check(!visible(nudge), "Switching to another listed app or editing rules preserves the snooze")
        frontmost = browser
        site.set("studio.example.org")
        let previousReads = site.reads
        clock.finish()
        await wait { site.reads > previousReads }
        check(site.reads > previousReads, "Website is checked again at expiry")
        check(!visible(nudge), "Switching to work subdomain clears website reminder")
        site.set("example.org")
        await wait { visible(nudge) }
        check(visible(nudge), "Returning to the site starts a new visit")
        monitor.snooze(for: .seconds(60))
        await wait { clock.duration != nil }
        model.advance(to: model.timer.deadline!.addingTimeInterval(1))
        check(!visible(nudge) && visible(completion), "Muted completion replaces distraction with completion window")
        clock.finish()
        await Task.yield()
        model.primaryAction()
        check(!visible(completion) && !visible(nudge), "Break clears completion and suppresses reminders")
        model.reset()

        var visit = FocusVisit()
        visit.enter(.distraction("example.org"))
        visit.dismiss()
        visit.enter(.distraction("example.org"))
        check(visit.visible == nil, "Dismissal persists for current visit")
        visit.enter(nil)
        visit.enter(.distraction("example.org"))
        check(visit.visible == .distraction("example.org"), "Leaving rearms dismissal")
        for failure in failures { print("FAIL: \(failure)") }
        print("Focus reminder window checks " + (failures.isEmpty ? "passed" : "failed"))
        return failures.isEmpty ? 0 : 1
    }

    @MainActor
    private final class SnoozeClock {
        private(set) var duration: Duration?
        private var continuation: CheckedContinuation<Void, Never>?
        func sleep(for duration: Duration) async {
            await withCheckedContinuation { next in
                self.duration = duration
                continuation = next
            }
        }
        func finish() {
            duration = nil
            continuation?.resume()
            continuation = nil
        }
    }

    private static func wait(until ready: () -> Bool) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !ready(), ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    private final class TestSite: @unchecked Sendable {
        private let lock = NSLock()
        private var host: String?
        private var readCount = 0
        var reads: Int { lock.withLock { readCount } }
        func read() -> String? {
            lock.withLock {
                readCount += 1
                return host
            }
        }
        func set(_ value: String) { lock.withLock { host = value } }
    }
}
