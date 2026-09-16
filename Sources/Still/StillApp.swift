// Created 2026-09-15 · gpt-6-astra · Codex
import AppKit
import SwiftUI

@main
struct StillApp {
    static func main() {
        if CommandLine.arguments.contains("--self-test") { exit(AppModelSelfTest.run()) }
        if let index = CommandLine.arguments.firstIndex(of: "--journal"), CommandLine.arguments.count > index + 1 {
            let model = AppModel(syncJournalOnLaunch: false)
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
    private let panelAnimator = PanelAnimator()
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?
    private var appearanceObservation: NSKeyValueObservation?
    private var pendingWindowPreferences: DispatchWorkItem?
    private var windowSelfTest = false
    private var compactSize: NSSize {
        let scale = model.preferences.compactScale
        return NSSize(width: (128 * scale).rounded(), height: (52 * scale).rounded())
    }
    private let expandedSize = NSSize(width: 256, height: 274)

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowSelfTest = CommandLine.arguments.contains("--window-self-test")
        preview = windowSelfTest || CommandLine.arguments.contains("--preview")
        model = AppModel(preview: preview)
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: compactSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Still"
        panel.identifier = NSUserInterfaceItemIdentifier("StillFloatingTimer")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.animationBehavior = .none
        let hosting = NSHostingView(rootView: TimerView(model: model, panelState: panelState,
            toggleExpanded: { [weak self] in self?.setExpanded(true) },
            collapse: { [weak self] in self?.setExpanded(false) },
            showHistory: { [weak self] in self?.showHistory() },
            showSettings: { [weak self] in self?.showSettings() }))
        // This borderless panel owns its frame. Do not let SwiftUI install
        // content-size constraints while the compact/expanded hierarchy changes.
        hosting.sizingOptions = []
        panel.contentView = hosting
        placeWindow()
        model.onWindowPreferencesChanged = { [weak self] in self?.scheduleWindowPreferences() }
        applyWindowPreferences()
        if !windowSelfTest { setupMenuBar(); setupDismissal() }
        NotificationCenter.default.addObserver(self, selector: #selector(showTimer), name: .showStill, object: nil)
        // A nil appearance follows system changes for both the native material and SwiftUI.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateAppearance() }
        }
        panel.orderFrontRegardless()
        if windowSelfTest {
            Task { @MainActor in
                let result = await WindowSelfTest.run(panel: self.panel,
                    setScale: { self.model.preferences.compactScale = $0; self.model.savePreferences() },
                    setExpanded: { self.setExpanded($0) },
                    flushPreferences: { self.flushWindowPreferences() })
                exit(result)
            }
        }
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
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0,
              panel.frame != frame else { return }
        changingFrame = true
        // Commit the geometry without drawing an intermediate SwiftUI layout.
        // AppKit draws the new content on the following display pass.
        panel.setFrame(frame, display: false, animate: false)
        changingFrame = false
    }
    private func setExpanded(_ expanded: Bool) {
        flushWindowPreferences()
        guard panelState.expanded != expanded else { return }
        if expanded { model.inspiration.reload() }
        if expanded && !panelAnimator.isAnimating { compactFrame = panel.frame }
        panelState.expanded = expanded
        let target = expanded
            ? NSRect(x: compactFrame.midX - expandedSize.width / 2, y: compactFrame.maxY - expandedSize.height,
                     width: expandedSize.width, height: expandedSize.height)
            : compactFrame
        transitionPanel(to: fit(target), expanded: expanded)
        if expanded { panel.makeKeyAndOrderFront(nil) }
    }
    private func transitionPanel(to frame: NSRect, expanded: Bool) {
        let startReveal = panelState.expansion
        let endReveal: CGFloat = expanded ? 1 : 0
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.isMovableByWindowBackground = false
        panelAnimator.animate(from: panel.frame, to: frame,
                              duration: reduceMotion ? 0 : (expanded ? 0.30 : 0.24),
                              update: { [weak self] frame, progress in
            guard let self else { return }
            self.panelState.expansion = startReveal + (endReveal - startReveal) * progress
            self.setPanelFrame(frame)
        }, completion: { [weak self] in
            guard let self else { return }
            self.panel.isMovableByWindowBackground = true
            self.panel.invalidateShadow()
            if !self.panelState.expanded { self.panel.resignKey() }
        })
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
    private func scheduleWindowPreferences() {
        // Preference bindings fire during SwiftUI's update. Resize after that
        // transaction, coalescing slider events instead of re-entering layout.
        pendingWindowPreferences?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingWindowPreferences = nil
            self?.applyWindowPreferences()
        }
        pendingWindowPreferences = work
        DispatchQueue.main.async(execute: work)
    }
    private func flushWindowPreferences() {
        guard pendingWindowPreferences != nil else { return }
        pendingWindowPreferences?.cancel()
        pendingWindowPreferences = nil
        applyWindowPreferences()
    }
    private func applyWindowPreferences() {
        let level: NSWindow.Level = model.preferences.floatOnTop ? .floating : .normal
        if panel.level != level { panel.level = level }
        let oldSize = compactFrame.size
        compactFrame.size = compactSize
        compactFrame.origin.y += oldSize.height - compactSize.height
        compactFrame = fit(compactFrame)
        if !panelState.expanded {
            if panelAnimator.isAnimating { transitionPanel(to: compactFrame, expanded: false) }
            else { setPanelFrame(compactFrame) }
        }
        updateAppearance()
        saveFrame()
    }
    private func updateAppearance() {
        let theme = model.preferences.theme
        let appearance: NSAppearance? = theme == "light" ? NSAppearance(named: .aqua) : theme == "dark" ? NSAppearance(named: .darkAqua) : nil
        for window in [panel, historyWindow, settingsWindow].compactMap({ $0 }) {
            if window.appearance?.name != appearance?.name { window.appearance = appearance }
            if window !== panel { window.backgroundColor = .windowBackgroundColor }
        }
    }
    func windowDidMove(_ notification: Notification) {
        guard !changingFrame, !panelAnimator.isAnimating, notification.object as? NSWindow === panel else { return }
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
        panelAnimator.cancel()
        flushWindowPreferences()
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
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
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
