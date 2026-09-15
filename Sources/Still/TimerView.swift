// Created 2026-09-15 · gpt-6-astra · Codex
import SwiftUI
import StillCore

// Use the property-wrapper type explicitly; CLT SDKs may omit SwiftUI macro plugins.
typealias StoredViewState<Value> = SwiftUI.State<Value>

struct Palette {
    let background: Color
    let ink: Color
    let secondary: Color
    let accent: Color
    let wash: Color
    static func named(_ name: String) -> Palette {
        switch name {
        case "dusk": return Palette(background: Color(hex: 0x272B32), ink: Color(hex: 0xEDE9DF), secondary: Color(hex: 0xAFB3B7), accent: Color(hex: 0xD4B98A), wash: Color(hex: 0x454C57))
        case "clay": return Palette(background: Color(hex: 0xF6EDE6), ink: Color(hex: 0x714C40), secondary: Color(hex: 0x987B70), accent: Color(hex: 0xB77B56), wash: Color(hex: 0xE4C8B9))
        default: return Palette(background: Color(hex: 0xF6F4EC), ink: Color(hex: 0x3E5145), secondary: Color(hex: 0x858D7E), accent: Color(hex: 0xB39A67), wash: Color(hex: 0xDCE4D4))
        }
    }
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}

struct TimerView: View {
    @ObservedObject var model: AppModel
    var showHistory: () -> Void
    var showSettings: () -> Void
    var hide: () -> Void
    var resize: (CGFloat) -> Void
    @StoredViewState private var hovering = false
    private var palette: Palette { .named(model.preferences.theme) }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 320, geometry.size.height / 366)
            content
                .frame(width: 320, height: 366)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background {
                    RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                        .fill(palette.background)
                        .overlay(alignment: .topLeading) {
                            RadialGradient(colors: [palette.wash.opacity(0.65), .clear], center: .topLeading, startRadius: 0, endRadius: 250 * scale)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 30 * scale, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 30 * scale, style: .continuous).strokeBorder(palette.ink.opacity(0.12), lineWidth: 1))
                }
                .overlay(alignment: .bottomTrailing) {
                    ResizeGrip().frame(width: 22, height: 22).padding(7).opacity(hovering ? 0.5 : 0.15)
                }
        }
        .foregroundStyle(palette.ink)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .preferredColorScheme(model.preferences.theme == "dusk" ? .dark : .light)
    }
    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "leaf").font(.system(size: 13, weight: .medium))
                Text("STILL").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(3.4)
                Spacer()
                if model.storageError != nil {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).help(model.storageError ?? "")
                }
                Menu {
                    Button("Session history", action: showHistory)
                    Button("Preferences…", action: showSettings)
                    Divider()
                    Menu("Window size") {
                        Button("Small") { resize(0.78) }
                        Button("Medium") { resize(1) }
                        Button("Large") { resize(1.3) }
                    }
                    Toggle("Always on top", isOn: Binding(get: { model.preferences.floatOnTop }, set: { model.preferences.floatOnTop = $0; model.savePreferences() }))
                    Divider()
                    Button("Hide Still", action: hide)
                    Button("Quit Still") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium)).frame(width: 26, height: 25)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Still menu")
            }
            .frame(height: 28).padding(.horizontal, 26).padding(.top, 18)

            HStack(spacing: 3) {
                modeButton("Focus", mode: .focus)
                modeButton("Short rest", mode: .shortBreak)
                modeButton("Long rest", mode: .longBreak)
            }
            .padding(3).background(palette.ink.opacity(0.045), in: Capsule()).padding(.horizontal, 30).padding(.top, 10)

            ZStack {
                Dial(progress: model.progress, running: model.timer.phase == .running, complete: model.timer.phase == .completed, palette: palette)
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(model.minutes).font(.system(size: 68, weight: .regular, design: .serif)).tracking(-3)
                            .foregroundStyle(palette.ink)
                        Text(":" + model.seconds).font(.system(size: 25, weight: .regular, design: .serif))
                            .foregroundStyle(palette.secondary.opacity(0.8)).tracking(-0.6)
                    }
                    .monospacedDigit()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Time remaining")
                    .accessibilityValue("\(model.remaining / 60) minutes and \(model.remaining % 60) seconds")
                    Text(statusLabel).font(.system(size: 9, weight: .medium)).tracking(2.2).foregroundStyle(palette.secondary)
                }
                .offset(y: -2)
            }
            .frame(width: 176, height: 176).scaleEffect(0.9).frame(width: 158.4, height: 158.4).padding(.top, 10)

            Text(model.subtitle).font(.system(size: 11.5)).foregroundStyle(palette.secondary).padding(.top, 8)

            HStack(spacing: 10) {
                Button { model.primaryAction() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.timer.phase == .running ? "pause.fill" : model.timer.phase == .completed ? "arrow.right" : "play.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(model.primaryTitle).font(.system(size: 12, weight: .medium))
                    }
                    .frame(width: 152, height: 34)
                    .foregroundStyle(palette.background)
                    .background(palette.ink, in: Capsule())
                }
                .buttonStyle(.plain).keyboardShortcut(.space, modifiers: [])
                Button { model.reset() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 13)).frame(width: 32, height: 32)
                        .background(palette.ink.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain).help("Reset this timer • unfinished sessions are not counted")
                .accessibilityLabel("Reset timer")
            }
            .padding(.top, 16)

            Button(action: showHistory) {
                HStack(spacing: 9) {
                    HStack(spacing: 4) {
                        ForEach(0..<4) { index in
                            Circle().fill(index < (model.todaySessions.count == 0 ? 0 : ((model.todaySessions.count - 1) % 4 + 1)) ? palette.accent : palette.ink.opacity(0.10))
                                .frame(width: 4, height: 4)
                        }
                    }
                    Text("\(model.todaySessions.count) \(model.todaySessions.count == 1 ? "session" : "sessions") today")
                        .font(.system(size: 10)).foregroundStyle(palette.secondary)
                    Image(systemName: "arrow.up.right").font(.system(size: 7, weight: .medium)).foregroundStyle(palette.secondary.opacity(0.65))
                }
                .frame(height: 29)
            }
            .buttonStyle(.plain).help("View your local session history").padding(.top, 6)
            Spacer(minLength: 0)
        }
    }
    private var statusLabel: String {
        switch model.timer.phase {
        case .completed: return "WELL SPENT"
        case .paused: return "PAUSED"
        default: return model.timer.mode == .focus ? "SLOW & STEADY" : "JUST BREATHE"
        }
    }
    private func modeButton(_ title: String, mode: TimerMode) -> some View {
        Button { model.selectMode(mode) } label: {
            Text(title).font(.system(size: 10.5, weight: model.timer.mode == mode ? .semibold : .regular))
                .foregroundStyle(model.timer.mode == mode ? palette.ink : palette.secondary)
                .frame(maxWidth: .infinity).frame(height: 23)
                .background(model.timer.mode == mode ? palette.background : .clear, in: Capsule())
                .shadow(color: model.timer.mode == mode ? .black.opacity(0.035) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain).disabled(model.isInProgress)
        .help(model.isInProgress ? "Reset the current timer to change mode" : title)
    }
}

struct Dial: View {
    let progress: Double
    let running: Bool
    let complete: Bool
    let palette: Palette
    var body: some View {
        ZStack {
            Circle().stroke(palette.ink.opacity(0.085), lineWidth: 1).padding(9)
            ForEach(0..<60) { i in
                Capsule().fill(palette.ink.opacity(i % 5 == 0 ? 0.25 : 0.12))
                    .frame(width: 1, height: i % 5 == 0 ? 5 : 2.5)
                    .offset(y: -85).rotationEffect(.degrees(Double(i) * 6))
            }
            Circle().trim(from: 0, to: complete ? 1 : progress)
                .stroke(palette.ink.opacity(0.65), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(9)
            Circle().fill(palette.accent).frame(width: 5.5, height: 5.5)
                .overlay(Circle().stroke(palette.background, lineWidth: 1.5))
                .offset(y: -78.5).rotationEffect(.degrees(progress * 360))
        }
        .accessibilityHidden(true)
    }
}
