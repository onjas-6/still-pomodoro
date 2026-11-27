// Created 2026-11-27 · Claude Code
import AppKit
import Combine
import StillCore
import SwiftUI

// Research mode is an experience-sampling study, the method Pychyl's group used with
// pagers: at random moments, ask whether there is something else you should be doing and
// how it feels. Every scheduled check-in leaves exactly one journal note, including ones
// that were missed or fell inside a focus session, so the record has no gaps to explain.

/// The next study's settings and the study in progress.
struct ResearchSettings: Codable, Equatable {
    var days = ResearchStudy.defaultDays
    var promptsPerDay = ResearchStudy.defaultPrompts
    var windowStartMinute = ResearchStudy.defaultWindow.start
    var windowEndMinute = ResearchStudy.defaultWindow.end
    var study: ResearchStudy?

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        days = try values.decodeIfPresent(Int.self, forKey: .days) ?? ResearchStudy.defaultDays
        promptsPerDay = try values.decodeIfPresent(Int.self, forKey: .promptsPerDay) ?? ResearchStudy.defaultPrompts
        windowStartMinute = try values.decodeIfPresent(Int.self, forKey: .windowStartMinute) ?? ResearchStudy.defaultWindow.start
        windowEndMinute = try values.decodeIfPresent(Int.self, forKey: .windowEndMinute) ?? ResearchStudy.defaultWindow.end
        study = try values.decodeIfPresent(ResearchStudy.self, forKey: .study)
    }
}

@MainActor
final class ResearchStore: ObservableObject {
    @Published private(set) var settings = ResearchSettings()
    @Published private(set) var error: String?
    private let file: URL
    private let canSave: Bool

    init(directory: URL, preview: Bool) {
        file = directory.appendingPathComponent("research-study.json")
        var canSave = !preview
        if !preview, FileManager.default.fileExists(atPath: file.path) {
            do {
                settings = try JSONDecoder().decode(ResearchSettings.self, from: Data(contentsOf: file))
            } catch {
                // Keep the unreadable file untouched rather than replacing a running study.
                canSave = false
                self.error = "Could not read \(file.lastPathComponent). \(error.localizedDescription)"
            }
        }
        self.canSave = canSave
    }

    func update(_ change: (inout ResearchSettings) -> Void) {
        var next = settings
        change(&next)
        let window = ResearchStudy.normalizedWindow(start: next.windowStartMinute, end: next.windowEndMinute)
        next.windowStartMinute = window.start
        next.windowEndMinute = window.end
        next.days = min(max(next.days, ResearchStudy.dayRange.lowerBound), ResearchStudy.dayRange.upperBound)
        next.promptsPerDay = min(max(next.promptsPerDay, ResearchStudy.promptRange.lowerBound), ResearchStudy.promptRange.upperBound)
        guard next != settings else { return }
        settings = next
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(next).write(to: file, options: .atomic)
            error = nil
        } catch {
            self.error = "Could not save research settings. \(error.localizedDescription)"
        }
    }
}

/// What was on screen when a check-in arrived.
struct ResearchContext: Sendable {
    var appName: String?
    var bundleID: String?
    var windowTitle: String?
    var url: String?
    var host: String?
    var idleSeconds: Int
    var accessibility: Bool

    static func capture() async -> ResearchContext {
        let (name, bundle, pid) = await MainActor.run { () -> (String?, String?, pid_t?) in
            let app = NSWorkspace.shared.frontmostApplication
            return (app?.localizedName, app?.bundleIdentifier, app?.processIdentifier)
        }
        let isBrowser = bundle.map { BrowserLocation.browsers.contains($0.lowercased()) } ?? false
        var window: (title: String?, url: URL?) = (nil, nil)
        if let pid {
            window = await Task.detached(priority: .utility) {
                BrowserLocation.windowContext(pid: pid, isBrowser: isBrowser)
            }.value
        }
        return ResearchContext(
            appName: name, bundleID: bundle, windowTitle: window.title,
            url: window.url?.absoluteString,
            host: window.url.flatMap { $0.host }.flatMap(FocusTargets.domain),
            idleSeconds: Int(FocusInactivity.inputIdleSeconds().rounded()),
            accessibility: AXIsProcessTrusted())
    }

    var fields: [String: String] {
        var fields = ["idleSeconds": String(idleSeconds), "accessibility": accessibility ? "yes" : "no"]
        fields["app"] = appName
        fields["bundleID"] = bundleID
        fields["windowTitle"] = windowTitle
        fields["url"] = url
        fields["host"] = host
        return fields
    }

    /// "App — Window title · host", shortened for the Markdown row.
    var label: String {
        var parts = [appName ?? "Unknown app"]
        if let windowTitle { parts[0] += " — " + (windowTitle.count > 90 ? String(windowTitle.prefix(89)) + "…" : windowTitle) }
        if let host { parts.append(host) }
        return parts.joined(separator: " · ")
    }
}

enum ResearchFeeling: String, CaseIterable, Identifiable {
    case bored, unclear, worried, frustrated, tired, fine
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bored: return "Bored"
        case .unclear: return "Not sure where to start"
        case .worried: return "Worried it won’t be good"
        case .frustrated: return "Frustrated"
        case .tired: return "Tired"
        case .fine: return "Fine, just drifted"
        }
    }
}

enum ResearchAnswer {
    case onTrack
    case elsewhere(feeling: ResearchFeeling?, task: String)
    case skipped
}

struct ResearchStats {
    var due = 0, answered = 0, elsewhere = 0, onTrack = 0, missed = 0, skipped = 0, expired = 0, inFocus = 0

    var summary: String {
        let share = answered > 0 ? " (\(Int((Double(elsewhere) / Double(answered) * 100).rounded()))% of answers)" : ""
        return "\(due) check-ins · \(answered) answered · \(elsewhere) said something else\(share)"
    }
}

/// Schedules check-ins, shows them when you are at the Mac, and records every outcome.
@MainActor
final class ResearchSampler {
    enum Kind {
        static let checkIn = "research.check-in"
        static let study = "research.study"
    }
    /// A check-in that cannot be shown within this time is recorded as missed.
    static let lateLimit: TimeInterval = 45 * 60
    /// An unanswered check-in closes itself after this long.
    static let answerLimit: TimeInterval = 10 * 60
    /// Wait for the keyboard or trackpad to be used within this long before asking.
    static let idleLimit: TimeInterval = 120

    let store: ResearchStore
    private weak var model: AppModel?
    private let panel = ResearchPromptPanel()
    private var tick: AnyCancellable?
    private var wake: AnyCancellable?
    private var active: (prompt: ResearchPrompt, shownAt: Date, context: ResearchContext?)?
    private var pending: Set<String> = []
    private var practicing = false
    private let desktop = InactivityEnvironment()

    init(model: AppModel, store: ResearchStore) {
        self.model = model
        self.store = store
        panel.answer = { [weak self] answer in self?.finish(answer) }
        guard !model.isPreview else { return }
        // AppModel's clock only publishes while a timer runs, so check-ins keep their own
        // low-frequency clock. The tolerance lets macOS coalesce it with other wakeups.
        tick = Timer.publish(every: 15, tolerance: 5, on: .main, in: .common).autoconnect()
            .sink { [weak self] now in self?.evaluate(at: now) }
        wake = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluate(at: Date()) }
    }

    var study: ResearchStudy? { store.settings.study }

    /// Shows the check-in panel once without recording anything.
    func practice() {
        guard active == nil else { return }
        practicing = true
        panel.present(caption: "Practice check-in · not recorded")
    }

    func start(at now: Date = Date()) {
        guard let model else { return }
        let settings = store.settings
        let study = ResearchStudy(startedAt: now, days: settings.days, promptsPerDay: settings.promptsPerDay,
                                  windowStartMinute: settings.windowStartMinute, windowEndMinute: settings.windowEndMinute)
        store.update { $0.study = study }
        let window = Self.window(study)
        model.addNote(StillNote(kind: Kind.study, at: now,
            summary: "Research study started · \(study.days) days · \(study.promptsPerDay) check-ins a day · \(window)",
            fields: ["study": study.id.uuidString, "event": "started", "days": "\(study.days)",
                     "promptsPerDay": "\(study.promptsPerDay)", "window": window,
                     "scheduledEnd": Self.iso(study.scheduledEnd)]))
        evaluate(at: now)
    }

    func stop(at now: Date = Date()) {
        guard var study = store.settings.study, study.stoppedAt == nil, now < study.scheduledEnd else { return }
        closeActive(as: .expired, at: now)
        study.stoppedAt = now
        store.update { $0.study = study }
        // Anything already due but never shown counts as missed, so the summary is complete.
        for prompt in openPrompts(in: study, at: now) { record(prompt, .missed, context: nil, at: now) }
        recordEndIfNeeded(study, at: now)
    }

    /// Forget a finished study so a new one can be configured. Its notes stay in the journal.
    func clear() {
        guard let study = store.settings.study, !study.isActive(at: Date()) else { return }
        store.update { $0.study = nil }
    }

    func stats(at now: Date = Date()) -> ResearchStats {
        guard let study, let model else { return ResearchStats() }
        let id = study.id.uuidString
        var stats = ResearchStats()
        stats.due = study.prompts(through: now).count
        for note in model.notes where note.kind == Kind.checkIn && note["study"] == id {
            switch note["outcome"] {
            case Outcome.answered.rawValue:
                stats.answered += 1
                if note["elsewhere"] == "yes" { stats.elsewhere += 1 } else { stats.onTrack += 1 }
            case Outcome.missed.rawValue: stats.missed += 1
            case Outcome.skipped.rawValue: stats.skipped += 1
            case Outcome.expired.rawValue: stats.expired += 1
            case Outcome.inFocus.rawValue: stats.inFocus += 1
            default: break
            }
        }
        return stats
    }

    /// A one-line status for the menu bar and Preferences, or nil when no study is running.
    func status(at now: Date = Date()) -> String? {
        guard let study, study.isActive(at: now), let day = study.dayNumber(at: now) else { return nil }
        let stats = stats(at: now)
        return "Research · day \(day) of \(study.days) · \(stats.answered) answered"
    }

    // MARK: - Scheduling

    private enum Outcome: String {
        case answered, skipped, expired, missed
        case inFocus = "in-focus"
    }

    func evaluate(at now: Date) {
        guard let model, !model.isPreview else { return }
        guard let study else { closeActive(as: .expired, at: now); return }
        if now >= study.end {
            closeActive(as: .expired, at: now)
            recordMissed(in: study, at: now)
            // The last check-ins keep their grace period before the study is summarized.
            if study.stoppedAt != nil || now >= study.end.addingTimeInterval(Self.lateLimit) {
                recordEndIfNeeded(study, at: now)
            }
            return
        }
        recordMissed(in: study, at: now)
        if let active {
            if now.timeIntervalSince(active.shownAt) > Self.answerLimit { closeActive(as: .expired, at: now) }
            return
        }
        guard !practicing else { return }
        guard let next = openPrompts(in: study, at: now).first(where: { now.timeIntervalSince($0.date) <= Self.lateLimit }) else {
            return
        }
        if model.timer.mode == .focus && model.timer.phase == .running {
            // Already doing the intended thing: record the context without interrupting.
            capture(next) { [weak self] context in self?.record(next, .inFocus, context: context, at: Date()) }
            return
        }
        guard desktop.desktopAvailable(), FocusInactivity.inputIdleSeconds() < Self.idleLimit,
              !model.restReminderActive, !model.focusCompletionAlertActive else { return }
        present(next, in: study, at: now)
    }

    private func openPrompts(in study: ResearchStudy, at now: Date) -> [ResearchPrompt] {
        let recorded = Set(model?.notes.filter { $0.kind == Kind.checkIn }.compactMap { $0["prompt"] } ?? [])
        return study.prompts(through: now).filter {
            !recorded.contains($0.key) && !pending.contains($0.key) && $0.key != active?.prompt.key
        }
    }

    private func recordMissed(in study: ResearchStudy, at now: Date) {
        for prompt in openPrompts(in: study, at: now) where now.timeIntervalSince(prompt.date) > Self.lateLimit {
            record(prompt, .missed, context: nil, at: now)
        }
    }

    private func present(_ prompt: ResearchPrompt, in study: ResearchStudy, at now: Date) {
        guard let model else { return }
        active = (prompt, now, nil)
        panel.present(caption: "Check-in \(prompt.slot) of \(prompt.slots) today · day \(prompt.day) of \(study.days)")
        if model.preferences.soundEnabled { model.playTone(model.preferences.inactivityTone) }
        let key = prompt.key
        Task { [weak self] in
            let context = await ResearchContext.capture()
            if let self, self.active?.prompt.key == key { self.active?.context = context }
        }
    }

    private func finish(_ answer: ResearchAnswer) {
        if practicing {
            practicing = false
            panel.present(caption: nil)
            return
        }
        guard let active else { return }
        let now = Date()
        var extra = ["shownAt": Self.iso(active.shownAt), "respondedAt": Self.iso(now),
                     "responseSeconds": String(Int(now.timeIntervalSince(active.shownAt).rounded()))]
        let outcome: Outcome
        switch answer {
        case .onTrack:
            outcome = .answered
            extra["elsewhere"] = "no"
        case let .elsewhere(feeling, task):
            outcome = .answered
            extra["elsewhere"] = "yes"
            extra["feeling"] = feeling?.rawValue
            let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
            if !task.isEmpty { extra["task"] = task }
        case .skipped:
            outcome = .skipped
        }
        close(active, as: outcome, extra: extra, at: now)
    }

    private func closeActive(as outcome: Outcome, at now: Date) {
        guard let active else { return }
        close(active, as: outcome, extra: ["shownAt": Self.iso(active.shownAt)], at: now)
    }

    private func close(_ active: (prompt: ResearchPrompt, shownAt: Date, context: ResearchContext?),
                       as outcome: Outcome, extra: [String: String], at now: Date) {
        self.active = nil
        panel.present(caption: nil)
        if let context = active.context {
            record(active.prompt, outcome, context: context, extra: extra, at: now)
        } else {
            // Answered before the window details arrived; record them as soon as they do.
            capture(active.prompt) { [weak self] context in
                self?.record(active.prompt, outcome, context: context, extra: extra, at: now)
            }
        }
    }

    private func capture(_ prompt: ResearchPrompt, then finish: @escaping (ResearchContext) -> Void) {
        pending.insert(prompt.key)
        Task { [weak self] in
            let context = await ResearchContext.capture()
            guard let self else { return }
            self.pending.remove(prompt.key)
            finish(context)
        }
    }

    private func record(_ prompt: ResearchPrompt, _ outcome: Outcome, context: ResearchContext?,
                        extra: [String: String] = [:], at now: Date) {
        guard let model, let study else { return }
        var fields = context?.fields ?? [:]
        fields.merge(extra) { $1 }
        fields["study"] = study.id.uuidString
        fields["prompt"] = prompt.key
        fields["day"] = "\(prompt.day)"
        fields["days"] = "\(study.days)"
        fields["slot"] = "\(prompt.slot)"
        fields["slots"] = "\(prompt.slots)"
        fields["scheduledAt"] = Self.iso(prompt.date)
        fields["outcome"] = outcome.rawValue
        fields["timer"] = "\(model.timer.mode.rawValue) \(model.timer.phase.rawValue)"

        var detail: String
        switch outcome {
        case .answered where fields["elsewhere"] == "yes":
            detail = "**Should be doing something else**"
            if let feeling = fields["feeling"].flatMap(ResearchFeeling.init(rawValue:)) { detail += " · " + feeling.title }
            if let task = fields["task"] { detail += " · “\(task)”" }
        case .answered: detail = "On track"
        case .skipped: detail = "Skipped"
        case .expired: detail = "No answer"
        case .missed: detail = "Missed (away from the Mac)"
        case .inFocus: detail = "In a focus session"
        }
        if let context { detail += " · " + context.label }
        let summary = "Research check-in · day \(prompt.day) of \(study.days) · \(prompt.slot)/\(prompt.slots) · " + detail
        model.addNote(StillNote(kind: Kind.checkIn, at: now, summary: summary, fields: fields))
    }

    private func recordEndIfNeeded(_ study: ResearchStudy, at now: Date) {
        guard let model, !model.notes.contains(where: {
            $0.kind == Kind.study && $0["study"] == study.id.uuidString && $0["event"] == "ended"
        }) else { return }
        let stats = stats(at: now)
        let reason = study.stoppedAt.map { _ in "stopped early" } ?? "completed"
        model.addNote(StillNote(kind: Kind.study, at: now,
            summary: "Research study \(reason) · " + stats.summary,
            fields: ["study": study.id.uuidString, "event": "ended", "reason": reason,
                     "due": "\(stats.due)", "answered": "\(stats.answered)", "elsewhere": "\(stats.elsewhere)",
                     "onTrack": "\(stats.onTrack)", "missed": "\(stats.missed)", "skipped": "\(stats.skipped)",
                     "expired": "\(stats.expired)", "inFocus": "\(stats.inFocus)"]))
    }

    static func window(_ study: ResearchStudy) -> String {
        clock(study.windowStartMinute) + "–" + clock(study.windowEndMinute)
    }

    static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - Check-in panel

@MainActor
final class ResearchPromptPanel {
    var answer: ((ResearchAnswer) -> Void)?
    private var panel: NSPanel?

    func present(caption: String?) {
        guard let caption else {
            panel?.orderOut(nil)
            panel = nil
            return
        }
        // Keyboard input is needed for the optional task field, so the panel can become key
        // when clicked; it never activates Still or takes focus on its own.
        let window = panel ?? FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                            backing: .buffered, defer: false)
        window.title = "Still — Research check-in"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hidesOnDeactivate = false
        window.hasShadow = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: ResearchPromptView(caption: caption) { [weak self] in self?.answer?($0) })
        window.contentView = hosting
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            window.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 30,
                                   width: size.width, height: size.height), display: true)
        }
        window.orderFrontRegardless()
        panel = window
    }

    /// For layout review only: the hosting view of the visible panel.
    var contentView: NSView? { panel?.contentView }
}

struct ResearchPromptView: View {
    let caption: String
    let answer: (ResearchAnswer) -> Void
    @StoredViewState private var askingWhy: Bool
    @StoredViewState private var feeling: ResearchFeeling? = nil
    @StoredViewState private var task = ""
    private let accent = Color(red: 0.55, green: 0.63, blue: 0.55)

    init(caption: String, askingWhy: Bool = false, answer: @escaping (ResearchAnswer) -> Void) {
        self.caption = caption
        self.answer = answer
        _askingWhy = StoredViewState(initialValue: askingWhy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble").foregroundStyle(accent)
                Text(caption.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(1)
                    .foregroundStyle(.white.opacity(0.6))
            }
            if askingWhy { reasons } else { question }
        }
        .padding(20).frame(width: 380, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white).colorScheme(.dark)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.14, green: 0.17, blue: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.8), lineWidth: 1.5))
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Is there something else you should be doing right now?")
                .font(.system(size: 19, weight: .semibold, design: .serif)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Button("No, this is it") { answer(.onTrack) }.keyboardShortcut("n", modifiers: [])
                Button("Yes") { askingWhy = true }.keyboardShortcut("y", modifiers: [])
                Spacer()
                Button("Skip") { answer(.skipped) }.buttonStyle(.link).foregroundStyle(.white.opacity(0.6))
            }
            .controlSize(.large)
        }
    }

    private var reasons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How does that task feel?")
                .font(.system(size: 17, weight: .semibold, design: .serif)).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(ResearchFeeling.allCases) { option in
                    Button { feeling = option } label: {
                        Text(option.title).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity).frame(height: 28)
                            .background(.white.opacity(feeling == option ? 0.2 : 0.07), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(feeling == option ? 1 : 0), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(feeling == option ? "Selected" : "Not selected")
                }
            }
            TextField("What should you be doing? (optional)", text: $task)
                .textFieldStyle(.roundedBorder)
                .onSubmit { answer(.elsewhere(feeling: feeling, task: task)) }
            HStack {
                Button("Save") { answer(.elsewhere(feeling: feeling, task: task)) }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Skip") { answer(.skipped) }.buttonStyle(.link).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Preferences

struct ResearchPreferences: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: ResearchStore
    let sampler: ResearchSampler
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let study = store.settings.study {
                running(study)
            } else {
                setup
            }
            HStack {
                Text(AXIsProcessTrusted() ? "Window titles and pages are recorded with each answer."
                                          : "Window titles and pages need Accessibility access.")
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
                Spacer()
                if !AXIsProcessTrusted() {
                    Button("Allow access…") { BrowserLocation.requestAccess() }.buttonStyle(.link).font(.system(size: 11))
                }
            }
            if let error = store.error { Text(error).font(.system(size: 10)).foregroundStyle(.orange) }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("At random moments, Still asks whether there is something else you should be doing and how it feels. Each answer goes to your Markdown journal with the app, window title and page you were on. Missed check-ins are recorded too.")
                .font(.system(size: 11)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            stepperRow("Length", value: binding(\.days), range: ResearchStudy.dayRange, unit: "days")
            stepperRow("Check-ins per day", value: binding(\.promptsPerDay), range: ResearchStudy.promptRange, unit: "")
            HStack(spacing: 14) {
                DatePicker("Between", selection: minuteBinding(\.windowStartMinute), displayedComponents: .hourAndMinute)
                DatePicker("and", selection: minuteBinding(\.windowEndMinute), displayedComponents: .hourAndMinute)
            }
            .datePickerStyle(.field).font(.system(size: 12))
            HStack(spacing: 9) {
                Button("Start a \(store.settings.days)-day study") { sampler.start() }
                Button("Try a check-in") { sampler.practice() }.buttonStyle(.link).font(.system(size: 11))
            }
        }
    }

    private func running(_ study: ResearchStudy) -> some View {
        let now = Date()
        let stats = sampler.stats(at: now)
        let active = study.isActive(at: now)
        return VStack(alignment: .leading, spacing: 8) {
            Text(active ? "Day \(study.dayNumber(at: now) ?? 1) of \(study.days)" : (study.stoppedAt == nil ? "Study complete" : "Study stopped"))
                .font(.system(size: 13, weight: .semibold))
            Text(stats.summary).font(.system(size: 11)).foregroundStyle(palette.secondary)
            Text("\(study.promptsPerDay) check-ins a day at random times, \(ResearchSampler.window(study)). Times are never shown in advance.")
                .font(.system(size: 10)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 9) {
                if active {
                    Button("Stop study") { sampler.stop() }
                    Button("Try a check-in") { sampler.practice() }.buttonStyle(.link).font(.system(size: 11))
                } else {
                    Button("Set up a new study") { sampler.clear() }
                }
            }
            .controlSize(.small)
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Text(unit.isEmpty ? "\(value.wrappedValue)" : "\(value.wrappedValue) \(unit)").font(.system(size: 12)).monospacedDigit()
            Stepper(title, value: value, in: range).labelsHidden().fixedSize()
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ResearchSettings, Int>) -> Binding<Int> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in store.update { $0[keyPath: keyPath] = value } })
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<ResearchSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minute = store.settings[keyPath: keyPath] % (24 * 60)
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                var minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                // Midnight as an end time means the end of the day.
                if keyPath == \ResearchSettings.windowEndMinute && minute == 0 { minute = 24 * 60 }
                store.update { $0[keyPath: keyPath] = minute }
            })
    }
}
