// Created 2026-09-15 · gpt-6-astra · Codex
import SwiftUI
import StillCore

// Explicitly select the property wrapper on CLT SDKs without SwiftUI macro plugins.
typealias StoredViewState<Value> = SwiftUI.State<Value>

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}

@MainActor
final class PanelState: ObservableObject {
    @Published var expanded = false
    @Published var expansion: CGFloat = 0
}

struct TimerView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var panelState: PanelState
    var toggleExpanded: () -> Void
    var collapse: () -> Void
    var showHistory: () -> Void
    var showSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @StoredViewState private var hovering = false
    private var palette: Palette { .resolved(theme: model.preferences.theme, scheme: colorScheme, colorTheme: model.preferences.colorTheme) }
    private var expansion: CGFloat { panelState.expansion }
    private var hasProgress: Bool { model.timer.phase != .ready }
    private func blend(_ compact: CGFloat, _ expanded: CGFloat) -> CGFloat { compact + (expanded - compact) * expansion }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = model.preferences.compactScale
            // The time is a single persistent view; the surface opens around it.
            // Controls reveal only after there is room, so they never squeeze into the pill.
            let reveal = max(0, min(1, (expansion - 0.40) / 0.60))
            ZStack(alignment: .topLeading) {
                digits(size: blend(34 * scale, 36))
                    .opacity(model.timer.phase == .paused ? 0.65 : 1)
                    .position(x: size.width / 2, y: blend(size.height / 2 - (hasProgress ? 3 : 0), 35))

                QuietProgress(progress: model.progress, paused: model.timer.phase == .paused, palette: palette)
                    .frame(width: max(1, blend(size.width - 30 * scale, size.width - 36)), height: blend(1.6, 2))
                    .position(x: size.width / 2, y: blend(size.height - 7 * scale, 64))
                    .opacity(hasProgress ? 1 : 0)
                    .accessibilityHidden(!hasProgress)

                Button(action: collapse) {
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(palette.ink.opacity(0.045), in: Circle())
                }
                .buttonStyle(QuietButtonStyle())
                .help("Collapse · Esc").accessibilityLabel("Collapse timer")
                .position(x: size.width - 27, y: 27)
                .opacity(reveal).allowsHitTesting(panelState.expanded && expansion > 0.95)
                .accessibilityHidden(!panelState.expanded)

                if !panelState.expanded && expansion == 0 {
                    CompactInteraction(action: toggleExpanded, time: "\(model.remaining / 60) minutes, \(model.remaining % 60) seconds remaining")
                        .frame(width: size.width, height: size.height)
                        .help("Click for controls · drag to move")
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) {
                // Keep the fixed-width controls out of the compact layout's size proposal.
                // Opacity alone leaves AppKit-backed controls alive and laying out.
                // Remove them after the closing animation, keeping the reveal intact.
                if panelState.expanded || expansion > 0 {
                    VStack(spacing: 12) {
                        controls
                        InspirationView(store: model.inspiration, palette: palette)
                    }
                    .frame(width: 220)
                    .offset(x: (size.width - 220) / 2, y: 81 + 7 * (1 - reveal))
                    .opacity(reveal)
                    .allowsHitTesting(panelState.expanded && expansion > 0.95)
                    .accessibilityHidden(!panelState.expanded)
                }
            }
            .background {
                SoftSurface(palette: palette,
                            opacity: Double(blend(model.preferences.backgroundOpacity, 0.94)),
                            expansion: expansion,
                            cornerRadius: blend(22 * scale, 26),
                            hovering: hovering,
                            diffuse: model.preferences.edgeStyle == "diffuse")
            }
        }
        .onHover { hovering = $0 }
        .foregroundStyle(palette.ink)
        .preferredColorScheme(model.preferences.preferredColorScheme())
    }

    private func digits(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1.5) {
            Text(model.minutes).font(.system(size: size, weight: .medium, design: .rounded)).tracking(-1.4)
            Text(":" + model.seconds).font(.system(size: size * 0.42, weight: .regular, design: .rounded))
                .foregroundStyle(palette.ink.opacity(0.43))
        }
        .monospacedDigit().fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue("\(model.remaining / 60) minutes and \(model.remaining % 60) seconds")
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if model.isInProgress {
                HStack(spacing: 5) {
                    Circle().fill(palette.progress).frame(width: 3.5, height: 3.5)
                    Text(model.timer.mode == .focus ? "FOCUS" : "REST")
                    Text("·")
                    Text(model.timer.phase == .paused ? "PAUSED" : "\(Int(model.timer.duration / 60)) MIN")
                }
                .font(.system(size: 8.5, weight: .medium)).tracking(1.2).foregroundStyle(palette.secondary)
                HStack(spacing: 8) {
                    Button {
                        model.primaryAction()
                        if model.timer.phase == .running { collapse() }
                    } label: {
                        Label(model.timer.phase == .running ? "Pause" : "Continue", systemImage: model.timer.phase == .running ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).frame(height: 34)
                            .foregroundStyle(palette.background).background(palette.ink, in: Capsule())
                    }.buttonStyle(QuietButtonStyle())
                    Button { model.reset() } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 11)).frame(width: 34, height: 34)
                            .background(palette.ink.opacity(0.055), in: Circle())
                    }.buttonStyle(QuietButtonStyle()).help("Reset without counting a session").accessibilityLabel("Reset timer")
                }
            } else {
                Text(model.timer.phase == .completed ? "A MOMENT, WELL SPENT" : "MAKE ROOM FOR FOCUS")
                    .font(.system(size: 8.5, weight: .medium)).tracking(1.25).foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        Button(action: showSettings) {
                            Image(systemName: "pencil").font(.system(size: 10)).frame(width: 22, height: 22)
                        }
                        .buttonStyle(QuietButtonStyle()).foregroundStyle(palette.secondary)
                        .help("Edit focus presets").accessibilityLabel("Edit focus presets")
                    }
                HStack(spacing: 8) {
                    ForEach(model.preferences.focusPresets.indices, id: \.self) { index in
                        focusPreset(model.preferences.focusPresets[index], primary: index == 0)
                    }
                }
            }
            HStack(spacing: 12) {
                if model.isInProgress {
                    Button("\(model.todaySessions.count) today", action: showHistory)
                        .font(.system(size: 10)).buttonStyle(QuietButtonStyle())
                } else {
                    Menu {
                        Button("Short rest · \(model.preferences.shortBreakMinutes) min") { startBreak(.shortBreak) }
                        Button("Long rest · \(model.preferences.longBreakMinutes) min") { startBreak(.longBreak) }
                    } label: { Text("Take a break").font(.system(size: 10)) }
                        .menuStyle(.borderlessButton).fixedSize()
                }
                Spacer()
                if model.storageError != nil || model.journalError != nil {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        .help(model.journalError ?? model.storageError ?? "")
                }
                Button(action: showHistory) { Image(systemName: "clock.arrow.circlepath").font(.system(size: 11)).frame(width: 19, height: 20) }
                    .buttonStyle(QuietButtonStyle()).help("Session history").accessibilityLabel("Session history")
                Button(action: showSettings) { Image(systemName: "slider.horizontal.3").font(.system(size: 11)).frame(width: 19, height: 20) }
                    .buttonStyle(QuietButtonStyle()).help("Preferences").accessibilityLabel("Preferences")
            }.foregroundStyle(palette.secondary).frame(height: 20).padding(.top, 2)
        }
    }
    private func focusPreset(_ minutes: Int, primary: Bool) -> some View {
        Button {
            model.startFocus(minutes: minutes)
            collapse()
        } label: {
            HStack(spacing: 4) {
                Text("\(minutes)").font(.system(size: 15, weight: .medium, design: .rounded))
                Text("min").font(.system(size: 10))
            }
            .frame(maxWidth: .infinity).frame(height: 34)
            .foregroundStyle(primary ? palette.background : palette.ink)
            .background(primary ? palette.ink : palette.ink.opacity(0.055), in: Capsule())
        }.buttonStyle(QuietButtonStyle()).accessibilityLabel("Start \(minutes) minute focus")
    }
    private func startBreak(_ mode: TimerMode) { model.startBreak(mode); collapse() }
}

private struct SoftSurface: View {
    let palette: Palette
    let opacity: Double
    let expansion: CGFloat
    let cornerRadius: CGFloat
    let hovering: Bool
    let diffuse: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if diffuse && !reduceTransparency {
                // A translucent color wash fades entirely before the window edge.
                // Only the surface is masked; text and controls remain crisp.
                ZStack {
                    palette.background
                    LinearGradient(colors: [palette.wash.opacity(0.40), palette.background.opacity(0.10)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .opacity(opacity)
                .mask {
                    GeometryReader { geometry in
                        let feather = min(14, geometry.size.height * 0.12) * (1 - expansion) + 7 * expansion
                        RoundedRectangle(cornerRadius: max(8, cornerRadius - feather), style: .continuous)
                            .fill(.white).padding(feather * 0.85).blur(radius: feather)
                            .mask(LinearGradient(stops: edgeStops, startPoint: .top, endPoint: .bottom))
                            .mask(LinearGradient(stops: edgeStops, startPoint: .leading, endPoint: .trailing))
                    }
                }
            } else {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                ZStack {
                    if reduceTransparency { palette.background }
                    else {
                        GlassBackground(opacity: opacity)
                        LinearGradient(colors: [palette.wash.opacity(0.30 + 0.35 * expansion),
                                                palette.background.opacity(0.16 + 0.36 * expansion)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .clipShape(shape)
                .overlay(shape.inset(by: 0.5).stroke(
                    LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.13 : (hovering ? 0.48 : 0.34)),
                                            palette.ink.opacity(0.025)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                    .blur(radius: 0.35))
                .mask(shape.fill(.white).blur(radius: 0.35))
            }
        }
        .allowsHitTesting(false)
    }

    private var edgeStops: [Gradient.Stop] {
        [.init(color: .clear, location: 0), .init(color: .white, location: 0.045),
         .init(color: .white, location: 0.955), .init(color: .clear, location: 1)]
    }
}

private struct QuietProgress: View {
    let progress: Double
    let paused: Bool
    let palette: Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.ink.opacity(0.075))
                Capsule().fill(LinearGradient(colors: [palette.progress.opacity(0.55), palette.progress], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * min(1, max(0, progress)))
            }
            .opacity(paused ? 0.4 : 0.8)
            .animation(reduceMotion || paused ? nil : .linear(duration: 1), value: progress)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session progress")
        .accessibilityValue("\(Int(progress * 100)) percent complete")
        .allowsHitTesting(false)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { QuietButtonBody(configuration: configuration) }
}
private struct QuietButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @StoredViewState private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        configuration.label
            .brightness(hovering ? 0.035 : 0)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : (hovering ? 1.015 : 1)))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
            .onHover { hovering = $0 }
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
    private var mouseDownEvent: NSEvent?
    private var dragged = false
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    // The floating timer is usually inactive while the user works elsewhere.
    // Deliver the first press to our click/drag handling instead of consuming it
    // just to activate the panel.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func accessibilityPerformPress() -> Bool { action?(); return true }
    override func mouseDown(with event: NSEvent) {
        // Event coordinates stay consistent even when queued input is delivered
        // after the physical pointer has moved on.
        initialPoint = event.locationInWindow
        mouseDownEvent = event
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard !dragged, let mouseDownEvent else { return }
        let current = event.locationInWindow
        let dx = current.x - initialPoint.x, dy = current.y - initialPoint.y
        guard hypot(dx, dy) > 3 else { return }
        dragged = true
        self.mouseDownEvent = nil
        // Hand movement to WindowServer instead of setting the frame on each
        // mouse event. A native drag may consume mouseUp, so reset on mouseDown.
        window?.performDrag(with: mouseDownEvent)
    }
    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        if !dragged { action?() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 36 { action?() }
        else { super.keyDown(with: event) }
    }
}
