// Created 2026-09-15 · gpt-6-astra · Codex
import AppKit
import SwiftUI

@main
struct StillApp {
    static func main() {
        if CommandLine.arguments.contains("--self-test") { exit(AppModelSelfTest.run()) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var panel: FloatingPanel!
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var menu: NSMenu!
    private var preview = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        preview = CommandLine.arguments.contains("--preview")
        model = AppModel(preview: preview)
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 366), styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Still"
        panel.identifier = NSUserInterfaceItemIdentifier("StillFloatingTimer")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 240, height: 274.5)
        panel.maxSize = NSSize(width: 448, height: 512.4)
        panel.contentAspectRatio = NSSize(width: 320, height: 366)
        panel.delegate = self
        panel.animationBehavior = .utilityWindow
        panel.contentView = NSHostingView(rootView: TimerView(model: model, showHistory: { [weak self] in self?.showHistory() }, showSettings: { [weak self] in self?.showSettings() }, hide: { [weak self] in self?.panel.orderOut(nil) }, resize: { [weak self] scale in self?.resize(scale) }))
        placeWindow()
        model.onWindowPreferencesChanged = { [weak self] in self?.applyWindowPreferences() }
        applyWindowPreferences()
        setupMenuBar()
        NotificationCenter.default.addObserver(self, selector: #selector(showTimer), name: .showStill, object: nil)
        panel.orderFrontRegardless()
        if let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.render(to: path) }
        }
    }
    private func placeWindow() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        var frame = NSRect(x: visible.maxX - 352, y: visible.minY + 70, width: 320, height: 366)
        if !preview, let saved = UserDefaults.standard.string(forKey: "floatingFrame") {
            let candidate = NSRectFromString(saved)
            if candidate.width >= 240, candidate.width <= 448, candidate.height >= 274,
               NSScreen.screens.contains(where: { $0.visibleFrame.contains(candidate) }) { frame = candidate }
        }
        panel.setFrame(frame, display: false)
    }
    private func applyWindowPreferences() {
        panel.level = model.preferences.floatOnTop ? .floating : .normal
        let appearance = NSAppearance(named: model.preferences.theme == "dusk" ? .darkAqua : .aqua)
        for window in [panel, historyWindow, settingsWindow].compactMap({ $0 }) {
            window.appearance = appearance
            if window !== panel { window.backgroundColor = NSColor(Palette.named(model.preferences.theme).background) }
        }
    }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    private func saveFrame() { if !preview, panel != nil { UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "floatingFrame") } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showTimer(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.persist(); saveFrame() }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "leaf.circle", accessibilityDescription: "Still — focus timer")
        statusItem.button?.toolTip = "Still — a little room to focus"
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let info = NSMenuItem(title: "Still · \(model.minutes):\(model.seconds)", action: nil, keyEquivalent: "")
        menu.addItem(info)
        menu.addItem(.separator())
        addItem("Show timer", action: #selector(showTimer), key: "")
        addItem(model.primaryTitle, action: #selector(toggleTimer), key: "")
        addItem("Reset timer", action: #selector(resetTimer), key: "")
        menu.addItem(.separator())
        addItem("Session history", action: #selector(showHistory), key: "h")
        addItem("Preferences…", action: #selector(showSettings), key: ",")
        menu.addItem(.separator())
        addItem("Quit Still", action: #selector(quit), key: "q")
    }
    private func addItem(_ title: String, action: Selector, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
    @objc func showTimer() { panel.orderFrontRegardless() }
    @objc private func toggleTimer() { model.primaryAction() }
    @objc private func resetTimer() { model.reset() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showHistory() {
        if historyWindow == nil { historyWindow = detailWindow(title: "Still — Sessions", view: HistoryView(model: model)) }
        historyWindow?.center()
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showSettings() {
        if settingsWindow == nil { settingsWindow = detailWindow(title: "Still — Preferences", view: PreferencesView(model: model)) }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func detailWindow<V: View>(title: String, view: V) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.appearance = NSAppearance(named: model.preferences.theme == "dusk" ? .darkAqua : .aqua)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.backgroundColor = NSColor(model.preferences.theme == "dusk" ? Color(hex: 0x272B32) : Palette.named(model.preferences.theme).background)
        return window
    }
    private func resize(_ scale: CGFloat) {
        let frame = panel.frame
        let size = NSSize(width: 320 * scale, height: 366 * scale)
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true, animate: true)
    }
    private func render(to path: String) {
        guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }
}

struct ResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> GripView { GripView() }
    func updateNSView(_ view: GripView, context: Context) {}
}
final class GripView: NSView {
    private var initialPoint = NSPoint.zero
    private var initialFrame = NSRect.zero
    override var mouseDownCanMoveWindow: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.setStroke()
        for offset in [CGFloat(4), 9] {
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: bounds.maxX - offset - 5, y: 4))
            path.line(to: NSPoint(x: bounds.maxX - 4, y: offset + 5))
            path.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialPoint = NSEvent.mouseLocation
        initialFrame = window.frame
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = NSEvent.mouseLocation
        let delta = ((point.x - initialPoint.x) - (point.y - initialPoint.y) * 320 / 366) / 2
        let width = min(448, max(240, initialFrame.width + delta))
        let height = width * 366 / 320
        window.setFrame(NSRect(x: initialFrame.minX, y: initialFrame.maxY - height, width: width, height: height), display: true)
    }
}
