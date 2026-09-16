// Created 2026-09-15 · gpt-6-astra · Codex
import AppKit
import Darwin

/// Exercises the actual hosting tree, including native controls, with private data disabled.
/// Run locally in a graphical login session: Still --render-self-test.
@MainActor
enum RenderSelfTest {
    static func run(model: AppModel, setExpanded: (Bool) -> Void,
                    showSettings: () -> Void, closeSettings: () -> Void) async -> Int32 {
        precondition(model.isPreview, "Render diagnostics must never use a real user model")
        precondition(model.dataURL.path.contains("/Still-RenderSelfTest-"))
        setbuf(stdout, nil)
        model.preferences.soundEnabled = false
        model.preferences.notificationsEnabled = false
        model.preferences.edgeStyle = "diffuse"
        model.preferences.compactScale = 1.45
        model.savePreferences()
        var failures = 0
        for phase in ["ready", "running", "paused", "completed"] {
            switch phase {
            case "running": model.startFocus(minutes: 1)
            case "paused": model.primaryAction()
            case "completed":
                model.primaryAction()
                model.advance(to: model.timer.deadline!.addingTimeInterval(1))
            default: break
            }
            for expanded in [false, true] {
                setExpanded(expanded)
                try? await Task.sleep(nanoseconds: 600_000_000)
                let startCPU = cpuSeconds()
                let startWall = ProcessInfo.processInfo.systemUptime
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let percent = 100 * (cpuSeconds() - startCPU) / (ProcessInfo.processInfo.systemUptime - startWall)
                print(String(format: "Render %@ %@: %.1f%% CPU", phase, expanded ? "expanded" : "compact", percent))
                if percent > 50 { failures += 1 }
            }
            setExpanded(false)
        }
        showSettings()
        for scenario in ["settings-open", "settings-closed", "dark", "light", "glass", "diffuse"] {
            switch scenario {
            case "settings-closed": closeSettings()
            case "dark", "light": model.preferences.theme = scenario; model.savePreferences()
            case "glass", "diffuse": model.preferences.edgeStyle = scenario; model.savePreferences()
            default: break
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            let startCPU = cpuSeconds()
            let startWall = ProcessInfo.processInfo.systemUptime
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let percent = 100 * (cpuSeconds() - startCPU) / (ProcessInfo.processInfo.systemUptime - startWall)
            print(String(format: "Render %@: %.1f%% CPU", scenario, percent))
            if percent > 50 { failures += 1 }
        }
        print("Render self-test: \(failures == 0 ? "passed" : "FAILED") (\(failures) busy-loop scenarios)")
        return failures == 0 ? 0 : 1
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}
