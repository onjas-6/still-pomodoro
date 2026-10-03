// Created 2026-10-02 · Claude Opus 5.5
import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake for a chosen duration, like `caffeinate`.
///
/// With the lid open, an IOKit assertion prevents idle sleep. Closing the lid
/// always sleeps a Mac without an external display unless `pmset disablesleep`
/// is set, which needs administrator rights. For that, Still asks for the
/// password once per session and starts a small root watcher that restores
/// normal sleep when the session ends, Still quits, or the battery runs low.
enum OSAResult: Sendable {
    case success(String)
    case failure(String)
}

@MainActor
final class StayAwake: ObservableObject {
    static let presetMinutes = [60, 120, 240, 480]

    /// nil when off. `.distantFuture` means until turned off.
    @Published private(set) var until: Date?
    @Published private(set) var lidClosedActive = false
    @Published private(set) var isRequestingLidMode = false
    @Published var lidError: String?

    private var assertion: IOPMAssertionID = 0
    private var helperPID: pid_t?
    private var check: Timer?
    private let tokenURL: URL
    private let enabled: Bool

    init(directory: URL, enabled: Bool) {
        tokenURL = directory.appendingPathComponent("stay-awake.token")
        self.enabled = enabled
        // A previous Still that crashed leaves its token behind; its watcher has
        // already restored sleep because that process is gone.
        if enabled { try? FileManager.default.removeItem(at: tokenURL) }
    }

    var isActive: Bool { until != nil }

    func statusText() -> String {
        guard let until else { return "Off — your Mac sleeps normally" }
        let lid = lidClosedActive ? ", even with the lid closed" : " while the lid is open"
        if until == .distantFuture { return "Mac won't sleep until you turn this off" + lid }
        return "Mac won't sleep until \(until.formatted(date: .omitted, time: .shortened))" + lid
    }

    /// Compact status for the floating timer, such as "On until 3:00 PM · lid closed OK".
    func shortStatusText() -> String {
        guard let until else { return "Off" }
        let time = until == .distantFuture ? "On until you turn it off" : "On until " + until.formatted(date: .omitted, time: .shortened)
        return time + (lidClosedActive ? " · lid closed OK" : " · lid open only")
    }

    /// - Parameter minutes: nil keeps the Mac awake until turned off.
    func start(minutes: Int?, lidClosed: Bool) {
        let deadline = minutes.map { Date().addingTimeInterval(Double(max(1, $0)) * 60) } ?? .distantFuture
        until = deadline
        lidError = nil
        guard enabled else { return }
        if assertion == 0 {
            let reason = "Still is keeping your Mac awake" as CFString
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion)
            if result != kIOReturnSuccess { assertion = 0 }
        }
        if lidClosed {
            writeToken(deadline)
            if !helperIsAlive { requestLidMode() }
        } else {
            stopLidMode()
        }
        scheduleCheck()
    }

    func stop() {
        until = nil
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        stopLidMode()
        check?.invalidate(); check = nil
    }

    private func stopLidMode() {
        // The watcher notices within five seconds and restores normal sleep.
        try? FileManager.default.removeItem(at: tokenURL)
        lidClosedActive = false
    }

    private func scheduleCheck() {
        check?.invalidate()
        check = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh(now: Date = Date()) {
        guard let until else { return }
        if now >= until { stop(); return }
        if lidClosedActive && !helperIsAlive {
            // The watcher stopped on its own, for example on low battery.
            lidClosedActive = false
            try? FileManager.default.removeItem(at: tokenURL)
            lidError = "Lid-closed mode ended. Normal sleep is back."
        }
    }

    private var helperIsAlive: Bool {
        guard let helperPID else { return false }
        // The watcher runs as root, so a live process answers EPERM.
        return kill(helperPID, 0) == 0 || errno == EPERM
    }

    private func writeToken(_ deadline: Date) {
        let epoch = deadline == .distantFuture ? 0 : Int(deadline.timeIntervalSince1970.rounded(.up))
        try? FileManager.default.createDirectory(at: tokenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(epoch)\n".write(to: tokenURL, atomically: true, encoding: .utf8)
    }

    private func requestLidMode() {
        guard !isRequestingLidMode else { return }
        guard let script = Self.helperScript(token: tokenURL.path, pid: ProcessInfo.processInfo.processIdentifier) else {
            lidError = "Lid-closed mode is unavailable for this folder."
            return
        }
        isRequestingLidMode = true
        let source = "do shell script \"\(Self.appleScriptEscaped(script))\" with prompt \"Still wants to keep your Mac awake with the lid closed.\" with administrator privileges"
        Task.detached(priority: .userInitiated) {
            let result = Self.runOSAScript(source)
            await MainActor.run { [weak self] in self?.finishLidRequest(result) }
        }
    }

    private func finishLidRequest(_ result: OSAResult) {
        isRequestingLidMode = false
        switch result {
        case let .success(output):
            guard isActive, FileManager.default.fileExists(atPath: tokenURL.path) else { return }
            helperPID = pid_t(output.trimmingCharacters(in: .whitespacesAndNewlines))
            lidClosedActive = helperIsAlive
            if !lidClosedActive { lidError = "Could not start lid-closed mode." }
        case let .failure(message):
            try? FileManager.default.removeItem(at: tokenURL)
            lidClosedActive = false
            lidError = message.contains("-128") ? "Password cancelled. Staying awake only while the lid is open." : "Lid-closed mode failed: \(message)"
        }
    }

    /// The root watcher. It reads the deadline from the token on each pass, so
    /// changing the duration later needs no new password prompt.
    nonisolated static func helperScript(token: String, pid: Int32, pmset: String = "/usr/bin/pmset", interval: Int = 5) -> String? {
        guard !token.contains("'"), !pmset.contains("'") else { return nil }
        let loop = """
        T=$1; P=$2; M=$3
        while [ -f "$T" ] && /bin/kill -0 "$P" 2>/dev/null; do
          d=$(/bin/cat "$T" 2>/dev/null)
          case "$d" in ''|*[!0-9]*) break;; esac
          [ "$d" -ne 0 ] && [ "$(/bin/date +%s)" -ge "$d" ] && break
          b=$("$M" -g batt)
          case "$b" in *discharging*)
            p=$(echo "$b" | /usr/bin/grep -Eo '[0-9]+%' | /usr/bin/head -1 | /usr/bin/tr -d %)
            [ -n "$p" ] && [ "$p" -lt 10 ] && break;;
          esac
          /bin/sleep \(interval)
        done
        /bin/rm -f "$T"
        "$M" -a disablesleep 0
        """
        // Single quotes delimit the loop for `sh -c`, so the loop uses an
        // escaped-quote form for its own literals.
        let quotedLoop = "'" + loop.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "'\(pmset)' -a disablesleep 1 || exit 1; /bin/sh -c \(quotedLoop) still-awake '\(token)' \(pid) '\(pmset)' >/dev/null 2>&1 & echo $!"
    }

    nonisolated static func appleScriptEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private nonisolated static func runOSAScript(_ source: String) -> OSAResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do { try process.run() } catch { return .failure(error.localizedDescription) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus == 0 { return .success(String(decoding: data, as: UTF8.self)) }
        return .failure(String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
