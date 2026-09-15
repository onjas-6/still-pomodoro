// Created 2026-09-15 · gpt-6-astra · Codex
import AppKit
import SwiftUI

@main
struct StillApp {
    static func main() {
        if CommandLine.arguments.contains("--self-test") { exit(AppModelSelfTest.run()) }
        if let index = CommandLine.arguments.firstIndex(of: "--journal"), CommandLine.arguments.count > index + 1 {
            let model = AppModel()
            guard model.setJournalPath(CommandLine.arguments[index + 1]) else {
                fputs((model.journalError ?? "Could not set journal path") + "\n", stderr)
                exit(1)
            }
            print("Journal: " + model.preferences.journalPath)
            exit(0)
        }
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
    private let panelState = PanelState()
    private var statusItem: NSStatusItem!
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var menu: NSMenu!
    private var preview = false
    private var compactFrame = NSRect.zero
    private var changingFrame = false
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?
    private var appearanceObservation: NSKeyValueObservation?
    private var compactSize: NSSize {
        let scale = model.preferences.compactScale
        return NSSize(width: 128 * scale, height: 52 * scale)
    }
    private let expandedSize = NSSize(width: 256, height: 196)

    func applicationDidFinishLaunching(_ notification: Notification) {
        preview = CommandLine.arguments.contains("--preview")
        model = AppModel(preview: preview)
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: compactSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Still"
        panel.identifier = NSUserInterfaceItemIdentifier("StillFloatingTimer")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(rootView: TimerView(model: model, panelState: panelState,
            toggleExpanded: { [weak self] in self?.setExpanded(true) },
            collapse: { [weak self] in self?.setExpanded(false) },
            showHistory: { [weak self] in self?.showHistory() },
            showSettings: { [weak self] in self?.showSettings() }))
        placeWindow()
        model.onWindowPreferencesChanged = { [weak self] in self?.applyWindowPreferences() }
        applyWindowPreferences()
        setupMenuBar()
        setupDismissal()
        NotificationCenter.default.addObserver(self, selector: #selector(showTimer), name: .showStill, object: nil)
        // A nil appearance follows system changes for both the native material and SwiftUI.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateAppearance() }
        }
        panel.orderFrontRegardless()
    }
    private func placeWindow() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        var frame = NSRect(x: visible.maxX - compactSize.width - 30, y: visible.minY + 60, width: compactSize.width, height: compactSize.height)
        if !preview, let saved = UserDefaults.standard.string(forKey: "compactFrame") {
            let candidate = NSRectFromString(saved)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(candidate) }) {
                frame.origin = candidate.origin
            }
        }
        compactFrame = fit(frame)
        setPanelFrame(compactFrame)
    }
    private func screen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) } ?? panel.screen ?? NSScreen.main
    }
    private func fit(_ frame: NSRect) -> NSRect {
        guard let visible = screen(for: frame)?.visibleFrame else { return frame }
        return NSRect(x: min(max(frame.minX, visible.minX + 6), visible.maxX - frame.width - 6),
                      y: min(max(frame.minY, visible.minY + 6), visible.maxY - frame.height - 6),
                      width: frame.width, height: frame.height)
    }
    private func setPanelFrame(_ frame: NSRect) {
        changingFrame = true
        panel.setFrame(frame, display: true)
        changingFrame = false
    }
    private func setExpanded(_ expanded: Bool) {
        guard panelState.expanded != expanded else { return }
        if expanded {
            compactFrame = panel.frame
            panelState.expanded = true
            panel.hasShadow = true
            let frame = NSRect(x: compactFrame.midX - expandedSize.width / 2, y: compactFrame.maxY - expandedSize.height,
                               width: expandedSize.width, height: expandedSize.height)
            setPanelFrame(fit(frame))
            panel.makeKeyAndOrderFront(nil)
        } else {
            panelState.expanded = false
            panel.hasShadow = false
            setPanelFrame(fit(compactFrame))
            panel.resignKey()
        }
    }
    private func setupDismissal() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self, !self.panel.frame.contains(point) else { return }
                self.setExpanded(false)
            }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.window === self.panel, self.panelState.expanded {
                if event.keyCode == 53 { self.setExpanded(false); return nil }
                if event.keyCode == 49 {
                    self.model.primaryAction()
                    if self.model.timer.phase == .running { self.setExpanded(false) }
                    return nil
                }
            }
            return event
        }
    }
    private func applyWindowPreferences() {
        panel.level = model.preferences.floatOnTop ? .floating : .normal
        let oldSize = compactFrame.size
        compactFrame.size = compactSize
        compactFrame.origin.y += oldSize.height - compactSize.height
        compactFrame = fit(compactFrame)
        if !panelState.expanded { setPanelFrame(compactFrame) }
        updateAppearance()
        saveFrame()
    }
    private func updateAppearance() {
        let theme = model.preferences.theme
        let appearance: NSAppearance? = theme == "light" ? NSAppearance(named: .aqua) : theme == "dark" ? NSAppearance(named: .darkAqua) : nil
        for window in [panel, historyWindow, settingsWindow].compactMap({ $0 }) {
            window.appearance = appearance
            if window !== panel { window.backgroundColor = .windowBackgroundColor }
        }
    }
    func windowDidMove(_ notification: Notification) {
        guard !changingFrame, notification.object as? NSWindow === panel else { return }
        if panelState.expanded {
            compactFrame.origin = NSPoint(x: panel.frame.midX - compactFrame.width / 2, y: panel.frame.maxY - compactFrame.height)
        } else { compactFrame = panel.frame }
        saveFrame()
    }
    private func saveFrame() {
        if !preview { UserDefaults.standard.set(NSStringFromRect(compactFrame), forKey: "compactFrame") }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showTimer(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        model.persist(); saveFrame()
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
    }
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "leaf.circle", accessibilityDescription: "Still — focus timer")
        statusItem.button?.toolTip = "Still"
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Still", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "Still · \(model.minutes):\(model.seconds)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        addItem("Show timer", action: #selector(showTimer), key: "")
        addItem("Timer controls", action: #selector(showControls), key: "")
        addItem(model.primaryTitle, action: #selector(toggleTimer), key: "")
        addItem("Reset timer", action: #selector(resetTimer), key: "")
        menu.addItem(.separator())
        addItem("Session history", action: #selector(showHistory), key: "h")
        addItem("Open Markdown journal", action: #selector(openJournal), key: "")
        addItem("Preferences…", action: #selector(showSettings), key: ",")
        menu.addItem(.separator())
        addItem("Hide timer", action: #selector(hideTimer), key: "")
        addItem("Quit Still", action: #selector(quit), key: "q")
    }
    private func addItem(_ title: String, action: Selector, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
    @objc func showTimer() { panel.orderFrontRegardless() }
    @objc private func showControls() { showTimer(); setExpanded(true) }
    @objc private func hideTimer() { setExpanded(false); panel.orderOut(nil) }
    @objc private func toggleTimer() { model.primaryAction() }
    @objc private func resetTimer() { model.reset() }
    @objc private func openJournal() { model.openJournal() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showHistory() {
        setExpanded(false)
        if historyWindow == nil { historyWindow = detailWindow(title: "Still — Sessions", view: HistoryView(model: model)) }
        historyWindow?.center(); historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showSettings() {
        setExpanded(false)
        if settingsWindow == nil { settingsWindow = detailWindow(title: "Still — Preferences", view: PreferencesView(model: model)) }
        settingsWindow?.center(); settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func detailWindow<V: View>(title: String, view: V) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.backgroundColor = .windowBackgroundColor
        let theme = model.preferences.theme
        window.appearance = theme == "light" ? NSAppearance(named: .aqua) : theme == "dark" ? NSAppearance(named: .darkAqua) : nil
        return window
    }
}
