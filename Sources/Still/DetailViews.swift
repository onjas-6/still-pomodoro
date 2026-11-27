// Created 2026-09-15 · gpt-5.6-terra · Codex
import SwiftUI
import StillCore
import UniformTypeIdentifiers

/// Preferences are grouped by what they change, in the order most people adjust them.
enum PreferenceGroup: String, CaseIterable, Identifiable {
    case focus, reminders, research, bedtime, appearance, journal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .reminders: return "Focus reminders"
        case .research: return "Research mode"
        case .bedtime: return "Bedtime & alerts"
        case .appearance: return "Appearance"
        case .journal: return "Journal & Mac"
        }
    }

    /// A short label for the section links at the top of the window.
    var shortTitle: String {
        switch self {
        case .focus: return "Focus"
        case .reminders: return "Reminders"
        case .research: return "Research"
        case .bedtime: return "Bedtime"
        case .appearance: return "Look"
        case .journal: return "Journal"
        }
    }

    var subtitle: String {
        switch self {
        case .focus: return "How long you focus and rest."
        case .reminders: return "Nudges while a focus timer runs."
        case .research: return "Random check-ins that measure when and why you drift."
        case .bedtime: return "Your nightly stop-work reminder, sounds and notifications."
        case .appearance: return "How the floating timer looks."
        case .journal: return "Your Markdown record, personal phrases and keep-awake."
        }
    }

    var symbol: String {
        switch self {
        case .focus: return "timer"
        case .reminders: return "bell"
        case .research: return "questionmark.bubble"
        case .bedtime: return "moon"
        case .appearance: return "paintpalette"
        case .journal: return "book.closed"
        }
    }
}

/// A subsection title inside a preference group.
struct PreferenceSubheading: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).font(.system(size: 12, weight: .semibold)).accessibilityAddTraits(.isHeader)
    }
}

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    let focusTargets: FocusTargetStore
    @ObservedObject var shortcutOnOpenRunner: ShortcutOnOpenRunner
    let research: ResearchSampler
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StoredViewState private var journalPathDraft = ""
    @StoredViewState private var restMessageDraft = ""
    private var palette: Palette { .resolved(theme: model.preferences.theme, scheme: colorScheme, colorTheme: model.preferences.colorTheme) }

    var body: some View {
        settingsContent
        .frame(width: 440, height: min(790, (NSScreen.main?.visibleFrame.height ?? 900) - 80))
        .background(palette.background).foregroundStyle(palette.ink)
        .preferredColorScheme(model.preferences.preferredColorScheme())
        .onAppear {
            journalPathDraft = model.preferences.journalPath
            restMessageDraft = model.preferences.restMessage
        }
        .onChange(of: model.preferences.journalPath) { _, path in journalPathDraft = path }
        .onChange(of: model.preferences.focusMinutes) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.focusPresets) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.shortBreakMinutes) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.longBreakMinutes) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.theme) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.colorTheme) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.edgeStyle) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.compactScale) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.backgroundOpacity) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.floatOnTop) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.soundEnabled) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.notificationsEnabled) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.restReminderEnabled) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.stayAwakeMinutes) { _, _ in model.savePreferences() }
    }

    private var settingsContent: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                header(proxy)
                Rectangle().fill(palette.ink.opacity(0.08)).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        focusGroup
                        remindersGroup
                        researchGroup
                        bedtimeGroup
                        appearanceGroup
                        journalGroup
                        footer
                    }
                    .toggleStyle(.switch).controlSize(.small).tint(palette.ink)
                    .padding(.horizontal, 20).padding(.vertical, 16).frame(width: 440)
                }
            }
        }
    }

    /// The title and section links stay visible while the groups scroll.
    private func header(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preferences").font(.system(size: 26, design: .serif))
            HStack(spacing: 4) {
                ForEach(PreferenceGroup.allCases) { group in
                    Button { jump(to: group, proxy) } label: {
                        Text(group.shortTitle).font(.system(size: 11, weight: .medium)).fixedSize()
                            .padding(.horizontal, 8).frame(height: 24)
                            .background(palette.ink.opacity(0.06), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Go to " + group.title)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)
    }

    private func jump(to group: PreferenceGroup, _ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(group, anchor: .top)
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(group, anchor: .top) }
        }
    }

    private var focusGroup: some View {
        group(.focus) {
            subsection("Session length") {
                durationRow("Default focus", value: $model.preferences.focusMinutes, range: 1...180)
                presetRow
                note("Type a number, then press Return. Applies to your next session.")
            }
            separator
            subsection("Breaks") {
                durationRow("Short rest", value: $model.preferences.shortBreakMinutes, range: 1...60)
                durationRow("Long rest", value: $model.preferences.longBreakMinutes, range: 1...90)
            }
        }
    }

    private var presetRow: some View {
        HStack(spacing: 10) {
            Text("Start buttons").font(.system(size: 12))
            Spacer()
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 4) {
                    DurationField(title: "Focus preset \(index + 1)", value: presetBinding(index), range: 1...180)
                        .frame(width: 43, height: 22)
                    Text("min").font(.system(size: 10)).foregroundStyle(palette.secondary)
                }
            }
        }
    }

    private var remindersGroup: some View {
        group(.reminders) {
            FocusTargetPreferences(store: focusTargets, palette: palette)
            separator
            subsection("macOS Focus mode") {
                FocusShortcutPreferences(runner: shortcutOnOpenRunner, palette: palette)
            }
        }
    }

    private var researchGroup: some View {
        group(.research) {
            ResearchPreferences(model: model, store: research.store, sampler: research, palette: palette)
        }
    }

    private var bedtimeGroup: some View {
        group(.bedtime) {
            bedtimeSettings
            separator
            soundSettings
            separator
            notificationSettings
        }
    }

    private var appearanceGroup: some View {
        group(.appearance) {
            Picker("Mode", selection: $model.preferences.theme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            AppearanceOptions(model: model, palette: palette)
            separator
            sliderRow("Collapsed timer size", value: $model.preferences.compactScale, range: Preferences.compactScaleRange, display: "\(Int((model.preferences.compactScale * 100).rounded()))%")
            sliderRow("Background opacity", value: $model.preferences.backgroundOpacity, range: 0.15...0.9, display: "\(Int(model.preferences.backgroundOpacity * 100))%")
            Toggle("Float above other windows", isOn: $model.preferences.floatOnTop)
        }
    }

    private var journalGroup: some View {
        group(.journal) {
            journalSettings
            separator
            subsection("Inspiration") {
                InspirationPreferences(store: model.inspiration, palette: palette)
            }
            separator
            subsection("Keep Mac awake (no sleep)") {
                StayAwakePreferences(model: model, stayAwake: model.stayAwake, palette: palette)
            }
        }
    }

    private var journalSettings: some View {
        subsection("Markdown journal") {
            HStack(spacing: 8) {
                TextField("Journal path", text: $journalPathDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit(saveJournalPath)
                Button("Save path", action: saveJournalPath).controlSize(.small)
            }
            HStack(spacing: 9) {
                Button("Choose…", action: chooseJournal)
                Button("Use existing…", action: chooseExistingJournal)
                Button("Open Markdown") { model.openJournal() }
                Spacer()
            }
            .controlSize(.small)
            if !model.journalDisplayPath.isEmpty {
                note(model.journalDisplayPath).lineLimit(1).truncationMode(.middle)
            }
            if model.preferences.journalPath != JournalLocation.mySpaceJournal.path {
                Button("Use Desktop MySpace") {
                    journalPathDraft = JournalLocation.mySpaceJournal.path
                    saveJournalPath()
                }.controlSize(.small)
            }
            if model.journalIsBusy { note("Updating Markdown…") }
            if let error = model.journalError {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "lock.shield").font(.system(size: 13))
                Text("Only on this Mac. No accounts. No tracking.").font(.system(size: 11))
            }
            .foregroundStyle(palette.secondary)
            if let error = model.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(.horizontal, 4).padding(.top, 2)
    }

    /// One titled card per topic: a clear heading, a one-line purpose, then its settings.
    private func group<Content: View>(_ group: PreferenceGroup, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: group.symbol).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.progress).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title).font(.system(size: 18, weight: .semibold, design: .serif))
                    Text(group.subtitle).font(.system(size: 11)).foregroundStyle(palette.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .id(group)
    }

    private func subsection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            PreferenceSubheading(title)
            content()
        }
    }

    private var separator: some View {
        Rectangle().fill(palette.ink.opacity(0.07)).frame(height: 1)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bedtimeSettings: some View {
        subsection("Bedtime reminder") {
            Toggle("Remind me at bedtime", isOn: $model.preferences.restReminderEnabled)
            HStack(spacing: 18) {
                DatePicker("Bedtime", selection: restTimeBinding(\.restStartMinute), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: restTimeBinding(\.restEndMinute), displayedComponents: .hourAndMinute)
            }
            .datePickerStyle(.field)
            HStack {
                TextField("Reminder message", text: $restMessageDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveRestMessage)
                Button("Save message", action: saveRestMessage).buttonStyle(.link)
            }
            if model.preferences.restStartMinute == model.preferences.restEndMinute {
                Text("Choose different bedtime and end times.")
                    .font(.caption).foregroundStyle(.orange)
            } else if model.preferences.restReminderEnabled {
                HStack {
                    Text(model.bedtimeNotificationStatus)
                        .font(.caption).foregroundStyle(palette.secondary)
                    Spacer()
                    if model.notificationStatus != "Allowed" { notificationSettingsButton }
                }
                Text("While Still is open, the bedtime reminder can be snoozed for 5 minutes.")
                    .font(.caption).foregroundStyle(palette.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.syncRestNotification()
        }
    }

    private var notificationSettingsButton: some View {
        Button(model.notificationStatus == "Not requested" ? "Allow notifications" : "System Settings") {
            if model.notificationStatus == "Not requested" { model.enableNotifications() }
            else { model.openNotificationSettings() }
        }.buttonStyle(.link).font(.caption)
    }

    private var soundSettings: some View {
        subsection("Sounds") {
            Toggle("Play timer and inactivity sounds", isOn: $model.preferences.soundEnabled)
            soundRow("Timer sound", selection: $model.preferences.timerTone, choices: AlertTone.timerChoices)
            soundRow("Inactivity sound", selection: $model.preferences.inactivityTone, choices: AlertTone.allCases)
        }
        .onChange(of: model.preferences.timerTone) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.inactivityTone) { _, _ in model.savePreferences() }
    }

    private var notificationSettings: some View {
        subsection("Notifications") {
            Toggle("Notify when a timer ends", isOn: $model.preferences.notificationsEnabled)
            HStack(spacing: 8) {
                Text(model.notificationStatus).font(.system(size: 10)).foregroundStyle(palette.secondary)
                Spacer()
                notificationSettingsButton
            }
        }
    }

    private func soundRow(_ title: String, selection: Binding<AlertTone>, choices: [AlertTone]) -> some View {
        HStack(spacing: 8) {
            Picker(title, selection: selection) {
                ForEach(choices) { tone in
                    Text(tone.displayName).tag(tone)
                }
            }
            Spacer()
            Button("Preview") { model.playTone(selection.wrappedValue) }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .accessibilityLabel("Preview \(title.lowercased())")
        }
    }
    private func durationRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            DurationField(title: title, value: value, range: range).frame(width: 50, height: 22)
            Text("min").font(.system(size: 11)).foregroundStyle(palette.secondary)
            Stepper(title, value: value, in: range).labelsHidden().fixedSize()
        }
    }
    private func presetBinding(_ index: Int) -> Binding<Int> {
        Binding(get: { model.preferences.focusPresets[index] }, set: { model.preferences.focusPresets[index] = $0 })
    }
    private func restTimeBinding(_ keyPath: WritableKeyPath<Preferences, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minute = model.preferences[keyPath: keyPath]
                // The picker edits only a local clock time. Use an occurrence even if today's
                // daylight-saving transition skips that hour.
                let reference = Date(timeIntervalSinceReferenceDate: 0)
                let time = DateComponents(hour: minute / 60, minute: minute % 60)
                return Calendar.current.nextDate(after: reference, matching: time, matchingPolicy: .strict) ?? reference
            },
            set: { date in
                let calendar = Calendar.current
                model.preferences[keyPath: keyPath] = calendar.component(.hour, from: date) * 60
                    + calendar.component(.minute, from: date)
                model.savePreferences()
            }
        )
    }
    private func saveRestMessage() {
        model.preferences.restMessage = restMessageDraft
        model.savePreferences()
        restMessageDraft = model.preferences.restMessage
    }
    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 12))
            Slider(value: value, in: range, step: 0.05).frame(width: 120)
            Text(display).font(.system(size: 10)).monospacedDigit().foregroundStyle(palette.secondary).frame(width: 32, alignment: .trailing)
        }
    }
    private func saveJournalPath() { saveJournalPath(journalPathDraft) }
    private func saveJournalPath(_ path: String) {
        Task { _ = await model.setJournalPathAsync(path) }
    }
    private func chooseJournal() {
        let panel = NSSavePanel()
        panel.title = "Choose session journal"
        panel.message = "Existing contents are preserved."
        panel.allowedContentTypes = [UTType(filenameExtension: "md")!]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = journalPathDraft.isEmpty ? "Still sessions.md" : URL(fileURLWithPath: journalPathDraft).lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveJournalPath(url.path)
    }
    private func chooseExistingJournal() {
        let panel = NSOpenPanel()
        panel.title = "Open session journal"
        panel.message = "Still appends completed focus sessions and preserves existing contents."
        panel.allowedContentTypes = [UTType(filenameExtension: "md")!]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveJournalPath(url.path)
    }
}

private struct FocusShortcutPreferences: View {
    @AppStorage(ShortcutOnOpenRunner.openPreferenceKey) private var openShortcutName = ""
    @AppStorage(ShortcutOnOpenRunner.endPreferenceKey) private var endShortcutName = ""
    @ObservedObject var runner: ShortcutOnOpenRunner
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            shortcutNameField("On open or focus start", text: $openShortcutName)
            shortcutNameField("On focus end", text: $endShortcutName)
            Text("Enter Apple shortcut names to control a macOS Focus. Leave a field blank to skip that action.")
                .font(.system(size: 10)).foregroundStyle(palette.secondary)
            if let error = runner.errorMessage {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
    }

    private func shortcutNameField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12))
            TextField("Shortcut name", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
        }
    }
}

private struct StayAwakePreferences: View {
    @ObservedObject var model: AppModel
    @ObservedObject var stayAwake: StayAwake
    let palette: Palette

    var body: some View {
        HStack {
            Text("Don't let my Mac sleep for").font(.system(size: 12))
            Spacer()
            DurationField(title: "Stay awake minutes", value: $model.preferences.stayAwakeMinutes, range: 1...1440)
                .frame(width: 50, height: 22)
            Text("min").font(.system(size: 11)).foregroundStyle(palette.secondary)
            Stepper("Stay awake minutes", value: $model.preferences.stayAwakeMinutes, in: 1...1440, step: 30).labelsHidden().fixedSize()
        }
        Toggle("Also with the lid closed", isOn: Binding(get: { model.preferences.stayAwakeLidClosed },
                                                       set: { model.setStayAwakeLidClosed($0) }))
        HStack(spacing: 9) {
            if stayAwake.isActive {
                Button("Let my Mac sleep again") { stayAwake.stop() }
            } else {
                Button("Start · \(StayAwakePreferences.format(model.preferences.stayAwakeMinutes))") {
                    model.startStayAwake(minutes: model.preferences.stayAwakeMinutes)
                }
                Button("Until I turn it off") { model.startStayAwake(minutes: nil) }
            }
            Spacer()
            Text(stayAwake.isRequestingLidMode ? "Waiting for password…" : stayAwake.statusText())
                .font(.system(size: 10)).foregroundStyle(palette.secondary)
        }
        .controlSize(.small)
        Text("Like caffeinate: downloads and builds keep running. Lid-closed mode asks for your password once, then restores normal sleep when time is up, Still quits, or the battery drops below 10%.")
            .font(.system(size: 10)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
        if let error = stayAwake.lidError {
            Text(error).font(.system(size: 10)).foregroundStyle(.orange)
        }
    }

    static func format(_ minutes: Int) -> String {
        if minutes % 60 == 0 { return "\(minutes / 60) h" }
        return minutes > 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    var editGoal: () -> Void
    @StoredViewState private var exportError: String? = nil
    @StoredViewState private var expandedDays: Set<String> = []
    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { .resolved(theme: model.preferences.theme, scheme: colorScheme, colorTheme: model.preferences.colorTheme) }
    private var week: [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: model.now) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Daily Overview").font(.system(size: 29, design: .serif))
                Spacer()
                Button { model.openJournal() } label: { Image(systemName: "doc.text") }
                    .buttonStyle(.plain).help("Open Markdown journal").accessibilityLabel("Open Markdown journal")
                Button(action: export) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.plain).help("Export completed sessions as JSON").accessibilityLabel("Export completed sessions")
            }
            HStack(spacing: 12) {
                metric(model.today.progressText, "SESSIONS TODAY")
                metric("\(model.today.minutes)m", "FOCUS TODAY")
                Button(model.today.goal == nil ? "Set daily goal…" : "Edit goal…", action: editGoal)
                    .controlSize(.small)
            }
            weekChart
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Set(model.days.keys).union([model.todayID]).sorted(by: >), id: \.self) { id in
                        dayRow(model.days[id] ?? FocusDay(id: id))
                        Divider().opacity(0.45)
                    }
                }
            }.frame(minHeight: 120, maxHeight: .infinity)
            if let error = model.journalError ?? model.storageError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Text("\(model.sessions.count) sessions · \(model.totalMinutes) focused minutes, all time")
                .font(.caption).foregroundStyle(palette.secondary)
        }
        .padding(26).frame(width: 460, height: min(545, (NSScreen.main?.visibleFrame.height ?? 900) - 80))
        .background(palette.background).foregroundStyle(palette.ink)
        .preferredColorScheme(model.preferences.preferredColorScheme())
        .onAppear { expandedDays.insert(model.todayID) }
        .onChange(of: model.todayID) { _, id in expandedDays.insert(id) }
        .alert("Could not export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private var weekChart: some View {
        let days = week.map { date in
            let id = DailyEvent.dayID(for: date)
            return model.days[id] ?? FocusDay(id: id)
        }
        let peak = max(1, days.map(\.completed).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 12) {
            ForEach(Array(zip(week, days)), id: \.1.id) { date, day in
                VStack(spacing: 4) {
                    Text(day.completed == 0 ? "" : "\(day.completed)").font(.caption2)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.id == model.todayID ? palette.ink : palette.wash)
                        .frame(height: max(3, 32 * CGFloat(day.completed) / CGFloat(peak)))
                    Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .help("\(day.id) · \(day.progressText) · \(day.status(isToday: day.id == model.todayID))")
            }
        }.foregroundStyle(palette.secondary).frame(height: 68, alignment: .bottom)
    }

    private func dayRow(_ day: FocusDay) -> some View {
        let today = day.id == model.todayID
        let expanded = Binding(get: { expandedDays.contains(day.id) }, set: { show in
            if show { expandedDays.insert(day.id) } else { expandedDays.remove(day.id) }
        })
        return DisclosureGroup(isExpanded: expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if day.activity.isEmpty {
                    Text("No sessions recorded.").foregroundStyle(palette.secondary)
                }
                ForEach(day.activity) { item in
                    HStack {
                        Image(systemName: item.symbol).frame(width: 14)
                        Text(item.detail)
                        Spacer()
                        Text(item.timeLabel).monospacedDigit().foregroundStyle(palette.secondary)
                    }
                }
            }.font(.caption).padding(.vertical, 5)
        } label: {
            HStack {
                Text(today ? "Today" : day.id).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(day.progressText).monospacedDigit()
                Text(day.status(isToday: today)).foregroundStyle(palette.secondary)
            }.font(.caption)
        }.padding(.vertical, 9)
    }
    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value).font(.system(size: 31, design: .serif))
            Text(caption).font(.system(size: 8, weight: .medium)).tracking(1.1).foregroundStyle(palette.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Still-sessions.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(model.sessions).write(to: url, options: .atomic)
        } catch { exportError = error.localizedDescription }
    }
}
