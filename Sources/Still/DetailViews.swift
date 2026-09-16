// Created 2026-09-15 · gpt-5.6-terra · Codex
import SwiftUI
import StillCore
import UniformTypeIdentifiers

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @StoredViewState private var journalPathDraft = ""
    private var palette: Palette { .resolved(theme: model.preferences.theme, scheme: colorScheme) }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your rhythm.").font(.system(size: 27, design: .serif))
                Text("A few small things to make Still yours.").font(.system(size: 12)).foregroundStyle(palette.secondary)
            }

            section("FOCUS") {
                durationRow("Default focus", value: $model.preferences.focusMinutes, range: 1...180)
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
                Text("Type a number, then press Return. Applies to your next session.")
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
            }

            section("BREAKS") {
                durationRow("Short rest", value: $model.preferences.shortBreakMinutes, range: 1...60)
                durationRow("Long rest", value: $model.preferences.longBreakMinutes, range: 1...90)
            }

            section("APPEARANCE") {
                Picker("Theme", selection: $model.preferences.theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)

                sliderRow("Collapsed timer size", value: $model.preferences.compactScale, range: 0.8...1.4, display: "\(Int(model.preferences.compactScale * 100))%")
                sliderRow("Background opacity", value: $model.preferences.backgroundOpacity, range: 0.15...0.9, display: "\(Int(model.preferences.backgroundOpacity * 100))%")
                Toggle("Float above other windows", isOn: $model.preferences.floatOnTop)
            }

            section("ALERTS") {
                HStack {
                    Toggle("Soft completion chime", isOn: $model.preferences.soundEnabled)
                    Spacer()
                    Button("Listen") { model.playChime() }.buttonStyle(.link).font(.system(size: 11))
                }
                Toggle("Notify when a timer ends", isOn: $model.preferences.notificationsEnabled)
                HStack(spacing: 8) {
                    Text(model.notificationStatus).font(.system(size: 10)).foregroundStyle(palette.secondary)
                    Spacer()
                    Button(model.notificationStatus == "Not requested" ? "Allow notifications" : "System Settings") {
                        if model.notificationStatus == "Not requested" { model.enableNotifications() }
                        else { model.openNotificationSettings() }
                    }.buttonStyle(.link).font(.system(size: 10))
                }
            }

            section("MARKDOWN JOURNAL") {
                TextField("Journal path", text: $journalPathDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                HStack(spacing: 9) {
                    Button("Save path", action: saveJournalPath)
                    Button("Choose…", action: chooseJournal)
                    Button("Use existing…", action: chooseExistingJournal)
                    Button("Open Markdown") { model.openJournal() }
                    Spacer()
                }
                .controlSize(.small)
                if !model.journalDisplayPath.isEmpty {
                    Text(model.journalDisplayPath).font(.system(size: 10)).foregroundStyle(palette.secondary).lineLimit(1).truncationMode(.middle)
                }
                if model.journalIsBusy {
                    Text("Updating Markdown…").font(.system(size: 10)).foregroundStyle(palette.secondary)
                }
                if let error = model.journalError {
                    Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                }
            }

            section("INSPIRATION") {
                InspirationPreferences(store: model.inspiration, palette: palette)
            }

            Divider().overlay(palette.ink.opacity(0.07))
            HStack {
                Image(systemName: "lock.shield").font(.system(size: 13))
                Text("Only on this Mac. No accounts. No tracking.").font(.system(size: 11))
            }.foregroundStyle(palette.secondary)
            if let error = model.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .toggleStyle(.switch).controlSize(.small).tint(palette.ink)
        .padding(28).frame(width: 440)
        }
        .frame(width: 440, height: min(790, (NSScreen.main?.visibleFrame.height ?? 900) - 80))
        .background(palette.background).foregroundStyle(palette.ink)
        .preferredColorScheme(model.preferences.preferredColorScheme())
        .onAppear { journalPathDraft = model.preferences.journalPath }
        .onChange(of: model.preferences.journalPath) { _, path in journalPathDraft = path }
        .onChange(of: model.preferences.focusMinutes) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.focusPresets) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.shortBreakMinutes) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.longBreakMinutes) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.theme) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.compactScale) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.backgroundOpacity) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.floatOnTop) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.soundEnabled) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.notificationsEnabled) { _, _ in model.savePreferences() }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(palette.secondary)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label(title)
            content()
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

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @StoredViewState private var exportError: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { .resolved(theme: model.preferences.theme, scheme: colorScheme) }
    private var days: [Date] { (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: model.now)) } }
    private func count(_ day: Date) -> Int { model.sessions.filter { Calendar.current.isDate($0.completedAt, inSameDayAs: day) }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Time, well spent.").font(.system(size: 29, design: .serif))
                    Text("Small beginnings add up.").font(.system(size: 12)).foregroundStyle(palette.secondary)
                }
                Spacer()
                HStack(spacing: 12) {
                    Button { model.openJournal() } label: { Image(systemName: "doc.text") }
                        .buttonStyle(.plain).help("Open session journal")
                    Button(action: export) { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(.plain).help("Export session history as JSON")
                }
            }
            HStack(spacing: 0) {
                metric("\(model.todaySessions.count)", "TODAY")
                metric("\(model.todayMinutes)m", "FOCUS TODAY")
                metric("\(model.sessions.count)", "ALL SESSIONS")
            }.padding(.vertical, 12)
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 7) {
                        Text(count(day) == 0 ? "" : "\(count(day))").font(.system(size: 10)).foregroundStyle(palette.secondary)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Calendar.current.isDateInToday(day) ? palette.ink : palette.wash)
                            .frame(height: max(3, 64 * CGFloat(count(day)) / CGFloat(max(1, days.map(count).max() ?? 1))))
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 10)).foregroundStyle(palette.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 100, alignment: .bottom)
            Divider()
            if model.sessions.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "leaf").font(.system(size: 25, weight: .ultraLight))
                    Text("Your first quiet moment awaits.").font(.system(size: 14, design: .serif))
                    Text("Completed focus sessions will appear here.").font(.system(size: 11)).foregroundStyle(palette.secondary)
                }.frame(maxWidth: .infinity).frame(height: 125)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.sessions.sorted { $0.completedAt > $1.completedAt }) { session in
                            HStack {
                                Image(systemName: "checkmark.circle").foregroundStyle(palette.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.completedAt.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 12))
                                    Text(session.startedAt.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(palette.secondary)
                                }
                                Spacer()
                                Text("\(Int(session.duration / 60)) min").font(.system(size: 12, design: .rounded))
                            }.padding(.vertical, 10)
                            Divider().opacity(0.4)
                        }
                    }
                }.frame(height: 165)
            }
            HStack {
                Text("\(model.totalMinutes) focused minutes, all time").font(.system(size: 10)).foregroundStyle(palette.secondary)
                Spacer()
                Image(systemName: "internaldrive").font(.system(size: 11)).foregroundStyle(palette.secondary)
            }
        }
        .padding(30).frame(width: 450).background(palette.background).foregroundStyle(palette.ink)
        .preferredColorScheme(model.preferences.preferredColorScheme())
        .alert("Could not export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
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
