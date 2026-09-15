// Created 2026-09-15 · gpt-6-astra · Codex
import SwiftUI
import StillCore
import UniformTypeIdentifiers

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    private var palette: Palette { .named(model.preferences.theme) }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your rhythm.").font(.system(size: 30, design: .serif))
                Text("A few small things to make Still yours.").font(.system(size: 12)).foregroundStyle(palette.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                label("TIME")
                durationRow("Focus", value: $model.preferences.focusMinutes, range: 1...180)
                durationRow("Short rest", value: $model.preferences.shortBreakMinutes, range: 1...60)
                durationRow("Long rest", value: $model.preferences.longBreakMinutes, range: 1...90)
                Text("Changes apply to your next timer.").font(.system(size: 10)).foregroundStyle(palette.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                label("ATMOSPHERE")
                HStack(spacing: 10) {
                    ForEach([("sage", "Sage"), ("clay", "Clay"), ("dusk", "Dusk")], id: \.0) { theme in
                        Button {
                            model.preferences.theme = theme.0
                            model.savePreferences()
                        } label: {
                            HStack(spacing: 7) {
                                Circle().fill(Palette.named(theme.0).ink).frame(width: 11, height: 11)
                                Text(theme.1).font(.system(size: 12))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Palette.named(theme.0).background, in: Capsule())
                            .foregroundStyle(Palette.named(theme.0).ink)
                            .overlay(Capsule().strokeBorder(model.preferences.theme == theme.0 ? palette.accent : palette.ink.opacity(0.1), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
                Toggle("Float above other windows", isOn: $model.preferences.floatOnTop)
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
            Divider().overlay(palette.ink.opacity(0.07))
            HStack {
                Image(systemName: "lock.shield").font(.system(size: 13))
                Text("Only on this Mac. No accounts. No tracking.").font(.system(size: 11))
            }.foregroundStyle(palette.secondary)
            if let error = model.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .toggleStyle(.switch).controlSize(.small).tint(palette.ink)
        .padding(30).frame(width: 430)
        .background(palette.background).foregroundStyle(palette.ink)
        .preferredColorScheme(model.preferences.theme == "dusk" ? .dark : .light)
        .onChange(of: model.preferences.focusMinutes) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.shortBreakMinutes) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.longBreakMinutes) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.floatOnTop) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.soundEnabled) { _, _ in model.savePreferences() }
        .onChange(of: model.preferences.notificationsEnabled) { _, _ in model.savePreferences() }
    }
    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(palette.secondary)
    }
    private func durationRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Text("\(value.wrappedValue) min").font(.system(size: 12)).monospacedDigit().foregroundStyle(palette.secondary)
            Stepper(title, value: value, in: range).labelsHidden().fixedSize()
        }
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @StoredViewState private var exportError: String? = nil
    private var palette: Palette { .named(model.preferences.theme) }
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
                Button(action: export) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.plain).help("Export session history as JSON")
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
        .preferredColorScheme(model.preferences.theme == "dusk" ? .dark : .light)
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
