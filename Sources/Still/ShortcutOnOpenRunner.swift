// Created 2026-11-25 · Codex
import Foundation
import StillCore

/// Runs Mac-local shortcuts in order without taking focus.
@MainActor
final class ShortcutOnOpenRunner: ObservableObject {
    static let openPreferenceKey = "focusShortcutOnOpen"
    static let endPreferenceKey = "focusShortcutOnEnd"

    @Published private(set) var errorMessage: String?
    private var pendingRequests: [Request] = []
    private var activeRequest: Request?
    private var activeProcess: Process?
    private var idleWaiters: [() -> Void] = []
    var hasPendingWork: Bool { activeRequest != nil || !pendingRequests.isEmpty }

    @discardableResult
    func runIfConfigured(preferenceKey: String, deadline: Date? = nil) -> Bool {
        guard let request = request(preferenceKey: preferenceKey, deadline: deadline) else { return false }
        if pendingRequests.last == request || (pendingRequests.isEmpty && activeRequest == request) { return true }
        pendingRequests.append(request)
        startNextIfNeeded()
        return true
    }

    func whenIdle(_ completion: @escaping () -> Void) {
        if !hasPendingWork { completion() }
        else { idleWaiters.append(completion) }
    }

    private func request(preferenceKey: String, deadline: Date?) -> Request? {
        let name = UserDefaults.standard.string(forKey: preferenceKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        return Request(preferenceKey: preferenceKey, name: name, deadline: deadline)
    }

    private func startNextIfNeeded() {
        guard activeRequest == nil else { return }
        guard !pendingRequests.isEmpty else {
            let waiters = idleWaiters
            idleWaiters.removeAll()
            waiters.forEach { $0() }
            return
        }
        let request = pendingRequests.removeFirst()
        activeRequest = request
        do {
            activeProcess = try launch(request) { [weak self] exitStatus in
                Task { @MainActor in self?.finish(request, exitStatus: exitStatus) }
            }
            errorMessage = nil
        } catch {
            activeRequest = nil
            errorMessage = "Could not run shortcut \u{201c}\(request.name)\u{201d}: \(error.localizedDescription)"
            startNextIfNeeded()
        }
    }

    private func finish(_ request: Request, exitStatus: Int32) {
        activeProcess = nil
        activeRequest = nil
        if exitStatus != 0 {
            errorMessage = "Shortcut \u{201c}\(request.name)\u{201d} exited with status \(exitStatus)."
        }
        startNextIfNeeded()
    }

    private func launch(_ request: Request, completion: @escaping (Int32) -> Void) throws -> Process {
        let inputURL = try request.deadline.map(writeDeadline)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", request.name] + (inputURL.map { ["--input-path", $0.path] } ?? [])
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finishedProcess in
            if let inputURL { try? FileManager.default.removeItem(at: inputURL) }
            let status = finishedProcess.terminationStatus
            completion(status)
        }
        do {
            try process.run()
        } catch {
            if let inputURL { try? FileManager.default.removeItem(at: inputURL) }
            throw error
        }
        return process
    }

    private func writeDeadline(_ deadline: Date) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Still-focus-deadline-\(UUID().uuidString).txt")
        let deadlineText = ISO8601DateFormatter().string(from: deadline)
        try Data(deadlineText.utf8).write(to: url, options: .atomic)
        return url
    }

    private struct Request: Equatable {
        let preferenceKey: String
        let name: String
        let deadline: Date?
    }
}

struct FocusShortcutLifecycle {
    private let runOpen: (Date?) -> Bool
    private let runEnd: () -> Bool
    private var systemFocusMayBeActive = false

    init(runOpen: @escaping (Date?) -> Bool, runEnd: @escaping () -> Bool) {
        self.runOpen = runOpen
        self.runEnd = runEnd
    }

    mutating func opened(with timer: TimerState) {
        systemFocusMayBeActive = runOpen(Self.deadline(for: timer)) || systemFocusMayBeActive
    }

    mutating func timerChanged(from previous: TimerState, to current: TimerState) {
        let wasActiveFocus = previous.mode == .focus && (previous.phase == .running || previous.phase == .paused)
        if wasActiveFocus && (current.phase == .ready || current.phase == .completed) {
            _ = endFocus()
            return
        }
        guard current.mode == .focus else { return }
        if current.phase == .running,
           previous.mode != .focus || previous.phase != .running || previous.deadline != current.deadline {
            systemFocusMayBeActive = runOpen(Self.deadline(for: current)) || systemFocusMayBeActive
        } else if previous.mode == .focus, previous.phase == .running, current.phase == .paused {
            systemFocusMayBeActive = runOpen(nil) || systemFocusMayBeActive
        }
    }

    @discardableResult
    mutating func focusCompleted() -> Bool {
        endFocus()
    }

    func shouldRunEndOnQuit(timer: TimerState) -> Bool {
        let hasScheduledFocusEnd = timer.mode == .focus && timer.phase == .running && timer.deadline != nil
        return !hasScheduledFocusEnd && (systemFocusMayBeActive || (timer.mode == .focus && timer.phase == .paused))
    }

    static func deadline(for timer: TimerState) -> Date? {
        timer.mode == .focus && timer.phase == .running ? timer.deadline : nil
    }

    private mutating func endFocus() -> Bool {
        let queued = runEnd()
        systemFocusMayBeActive = false
        return queued
    }
}
