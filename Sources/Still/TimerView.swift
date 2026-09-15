// Created 2026-09-15 · gpt-6-astra · Codex
import SwiftUI
import StillCore

// Explicitly select the property wrapper on CLT SDKs without SwiftUI macro plugins.
typealias StoredViewState<Value> = SwiftUI.State<Value>

struct Palette {
    let background: Color
    let ink: Color
    let secondary: Color
    let accent: Color
    let wash: Color
    static func resolved(theme: String, scheme: ColorScheme) -> Palette {
        let dark = theme == "dark" || (theme != "light" && scheme == .dark)
        if dark {
            return Palette(background: Color(hex: 0x252B29), ink: Color(hex: 0xF0F0E8), secondary: Color(hex: 0xB0BBB3), accent: Color(hex: 0xC6B184), wash: Color(hex: 0x47564B))
        }
        return Palette(background: Color(hex: 0xF4F4ED), ink: Color(hex: 0x344B3C), secondary: Color(hex: 0x758378), accent: Color(hex: 0x9B8356), wash: Color(hex: 0xDCE5D9))
    }
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}

@MainActor
final class PanelState: ObservableObject {
    @Published var expanded = false
}

struct TimerView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var panelState: PanelState
    var toggleExpanded: () -> Void
    var collapse: () -> Void
    var showHistory: () -> Void
    var showSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var palette: Palette { .resolved(theme: model.preferences.theme, scheme: colorScheme) }

    var body: some View {
        Group {
            if panelState.expanded { controls }
            else {
                ZStack {
                    digits(size: 34 * model.preferences.compactScale)
                        .opacity(model.timer.phase == .paused ? 0.6 : 1)
                    CompactInteraction(action: toggleExpanded, time: "\(model.remaining / 60) minutes, \(model.remaining % 60) seconds remaining")
                }
                .help("Click for controls · drag to move")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                if reduceTransparency { palette.background }
                else {
                    GlassBackground(opacity: panelState.expanded ? 0.94 : model.preferences.backgroundOpacity)
                    palette.background.opacity(panelState.expanded ? 0.5 : 0.08)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: panelState.expanded ? 22 : 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: panelState.expanded ? 22 : 17, style: .continuous)
                .strokeBorder(palette.ink.opacity(panelState.expanded ? 0.09 : 0.06), lineWidth: 0.7))
        }
        .foregroundStyle(palette.ink)
        .preferredColorScheme(model.preferences.preferredColorScheme())
    }
    private func digits(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(model.minutes).font(.system(size: size, weight: .medium, design: .rounded)).tracking(-1.8)
            Text(":" + model.seconds).font(.system(size: size * 0.43, weight: .regular, design: .rounded))
                .foregroundStyle(palette.ink.opacity(0.48))
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue("\(model.remaining / 60) minutes and \(model.remaining % 60) seconds")
    }
    private var controls: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                digits(size: 33)
                Spacer()
                Button(action: collapse) {
                    Image(systemName: "chevron.up").font(.system(size: 10, weight: .medium))
                        .frame(width: 24, height: 24).background(palette.ink.opacity(0.055), in: Circle())
                }.buttonStyle(.plain).help("Collapse · Esc").accessibilityLabel("Collapse timer")
            }
            if model.isInProgress {
                HStack {
                    Text(model.timer.mode == .focus ? "FOCUS" : "REST")
                    Text("·")
                    Text(model.timer.phase == .paused ? "PAUSED" : "\(Int(model.timer.duration / 60)) MIN")
                    Spacer()
                }
                .font(.system(size: 9, weight: .medium)).tracking(1.1).foregroundStyle(palette.secondary)
                HStack(spacing: 7) {
                    Button {
                        model.primaryAction()
                        if model.timer.phase == .running { collapse() }
                    } label: {
                        Label(model.timer.phase == .running ? "Pause" : "Continue", systemImage: model.timer.phase == .running ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).frame(height: 32)
                            .foregroundStyle(palette.background).background(palette.ink, in: Capsule())
                    }.buttonStyle(.plain)
                    Button { model.reset() } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 12)).frame(width: 33, height: 32)
                            .background(palette.ink.opacity(0.065), in: Capsule())
                    }.buttonStyle(.plain).help("Reset without counting a session").accessibilityLabel("Reset timer")
                }
            } else {
                HStack {
                    Text(model.timer.phase == .completed ? "NICELY DONE. WHAT’S NEXT?" : "START A FOCUS SESSION")
                        .font(.system(size: 8.5, weight: .medium)).tracking(0.9).foregroundStyle(palette.secondary)
                    Spacer()
                }
                HStack(spacing: 7) {
                    focusPreset(25)
                    focusPreset(50)
                    if ![25, 50].contains(model.preferences.focusMinutes) { focusPreset(model.preferences.focusMinutes) }
                }
            }
            HStack {
                if model.isInProgress {
                    Button("\(model.todaySessions.count) today", action: showHistory)
                        .font(.system(size: 10)).buttonStyle(.plain)
                } else {
                    Menu {
                        Button("Short rest · \(model.preferences.shortBreakMinutes) min") { startBreak(.shortBreak) }
                        Button("Long rest · \(model.preferences.longBreakMinutes) min") { startBreak(.longBreak) }
                    } label: {
                        Text("Take a break").font(.system(size: 10))
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                Spacer()
                if model.storageError != nil || model.journalError != nil {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        .help(model.journalError ?? model.storageError ?? "")
                }
                Button(action: showHistory) { Image(systemName: "clock.arrow.circlepath").font(.system(size: 11)) }
                    .buttonStyle(.plain).help("Session history").accessibilityLabel("Session history")
                Button(action: showSettings) { Image(systemName: "slider.horizontal.3").font(.system(size: 11)) }
                    .buttonStyle(.plain).help("Preferences").accessibilityLabel("Preferences")
            }.foregroundStyle(palette.secondary).frame(height: 16)
        }
        .padding(16)
    }
    private func focusPreset(_ minutes: Int) -> some View {
        Button {
            model.startFocus(minutes: minutes)
            collapse()
        } label: {
            HStack(spacing: 4) {
                Text("\(minutes)").font(.system(size: 15, weight: .medium, design: .rounded))
                Text("min").font(.system(size: 10))
            }
            .frame(maxWidth: .infinity).frame(height: 33)
            .foregroundStyle(minutes == 25 ? palette.background : palette.ink)
            .background(minutes == 25 ? palette.ink : palette.ink.opacity(0.075), in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel("Start \(minutes) minute focus")
    }
    private func startBreak(_ mode: TimerMode) {
        model.startBreak(mode)
        collapse()
    }
}

struct GlassBackground: NSViewRepresentable {
    var opacity: Double
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .popover
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.alphaValue = opacity }
}

struct CompactInteraction: NSViewRepresentable {
    var action: () -> Void
    var time: String
    func makeNSView(context: Context) -> CompactHitView { CompactHitView() }
    func updateNSView(_ view: CompactHitView, context: Context) {
        view.action = action
        view.setAccessibilityLabel("Show timer controls")
        view.setAccessibilityValue(time)
        view.setAccessibilityHelp("Click to expand. Drag to move the timer.")
    }
}
final class CompactHitView: NSView {
    var action: (() -> Void)?
    private var initialPoint = NSPoint.zero
    private var initialFrame = NSRect.zero
    private var dragged = false
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func accessibilityPerformPress() -> Bool { action?(); return true }
    override func mouseDown(with event: NSEvent) {
        initialPoint = NSEvent.mouseLocation
        initialFrame = window?.frame ?? .zero
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - initialPoint.x, dy = current.y - initialPoint.y
        if hypot(dx, dy) > 3 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: initialFrame.minX + dx, y: initialFrame.minY + dy)) }
    }
    override func mouseUp(with event: NSEvent) { if !dragged { action?() } }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 36 { action?() }
        else { super.keyDown(with: event) }
    }
}
