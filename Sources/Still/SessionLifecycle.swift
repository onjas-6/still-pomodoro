// Created 2026-11-27 · Claude Code
import Foundation
import StillCore

/// Records what was in progress when Still stops, so a quit or crash leaves a note instead
/// of a silent gap. Costs one small file write at launch and one at quit; nothing runs in
/// between.
@MainActor
enum SessionLifecycle {
    static let markerName = "running.json"

    private struct Marker: Codable {
        let launchedAt: Date
        let pid: Int32
    }

    enum Kind {
        static let quit = "app.quit"
        static let launch = "app.launch"
        static let uncleanExit = "app.unclean-exit"
    }

    /// At launch: if the previous run never reached a normal quit, record that; then mark
    /// this run as live. During a research study, the launch itself is noted for coverage.
    static func launched(model: AppModel, research: ResearchSampler, at now: Date = Date()) {
        guard !model.isPreview else { return }
        let marker = markerURL(for: model)
        if let data = try? Data(contentsOf: marker), let previous = try? JSONDecoder().decode(Marker.self, from: data) {
            let lastSaved = (try? FileManager.default.attributesOfItem(atPath: model.dataURL.path))?[.modificationDate] as? Date
            var fields = ["event": "unclean-exit", "previousLaunch": ResearchSampler.iso(previous.launchedAt)]
            var summary = "Still did not quit normally (crash, force quit or power loss) · that run started "
                + time(previous.launchedAt)
            if let lastSaved {
                fields["lastSaved"] = ResearchSampler.iso(lastSaved)
                summary += " · last saved " + time(lastSaved)
            }
            model.addNote(StillNote(kind: Kind.uncleanExit, at: now, summary: summary, fields: fields))
        }
        if let data = try? JSONEncoder().encode(Marker(launchedAt: now, pid: getpid())) {
            try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: marker, options: .atomic)
        }
        if let status = research.status(at: now) {
            model.addNote(StillNote(kind: Kind.launch, at: now, summary: "Still started · " + status,
                                    fields: ["event": "launch", "research": "active"]))
        }
    }

    /// At quit: close any open check-in with what was entered, note an unfinished timer or a
    /// running study, then clear the live marker. Synchronous so it completes before exit.
    static func quitting(model: AppModel, research: ResearchSampler, at now: Date = Date()) {
        guard !model.isPreview else { return }
        research.recordInterruption(reason: "quit", at: now)
        var parts: [String] = []
        var fields = ["event": "quit"]
        let timer = model.timer
        if timer.phase == .running || timer.phase == .paused {
            let elapsed = Int((timer.duration - timer.remaining(at: now)) / 60)
            let total = Int((timer.duration / 60).rounded())
            let state = timer.phase == .running ? "keeps counting down" : "stays paused"
            parts.append("\(timer.mode.title) \(elapsed) of \(total) min done, \(state) until Still reopens")
            fields["mode"] = timer.mode.rawValue
            fields["phase"] = timer.phase.rawValue
            fields["elapsedSeconds"] = String(Int(timer.duration - timer.remaining(at: now)))
            fields["durationSeconds"] = String(Int(timer.duration))
            if let deadline = timer.deadline { fields["deadline"] = ResearchSampler.iso(deadline) }
        }
        if let status = research.status(at: now) {
            parts.append(status)
            fields["research"] = "active"
        }
        if !parts.isEmpty {
            model.addNote(StillNote(kind: Kind.quit, at: now, summary: "Still quit · " + parts.joined(separator: " · "),
                                    fields: fields))
        }
        try? FileManager.default.removeItem(at: markerURL(for: model))
    }

    private static func markerURL(for model: AppModel) -> URL {
        model.dataURL.deletingLastPathComponent().appendingPathComponent(markerName)
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
