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
        let monitor = FocusReminderMonitor(model: model, store: store, frontmost: { frontmost },
                                          readSite: { _ in .site(site.read()) })
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
        site.set("studio.example.org")
        await wait { !visible(nudge) }
        check(!visible(nudge), "Switching to work subdomain clears website reminder")
        site.set("example.org")
        await wait { visible(nudge) }
        check(visible(nudge), "Returning to the site starts a new visit")
        model.advance(to: model.timer.deadline!.addingTimeInterval(1))
        check(!visible(nudge) && visible(completion), "Muted completion replaces distraction with completion window")
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

    private static func wait(until ready: () -> Bool) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !ready(), ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    private final class TestSite: @unchecked Sendable {
        private let lock = NSLock()
        private var host: String?
        func read() -> String? { lock.withLock { host } }
        func set(_ value: String) { lock.withLock { host = value } }
    }
}
