import AppKit
import SwiftUI

@MainActor
final class FocusNoticePanel {
    var dismiss: (() -> Void)?
    var snooze: ((Duration) -> Void)?
    private var panel: NSPanel?

    func present(_ notice: FocusNotice?) {
        guard let notice else {
            panel?.orderOut(nil)
            panel = nil
            return
        }
        let window = panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        window.title = "Still — Focus reminder"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hidesOnDeactivate = false
        window.hasShadow = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(
            rootView: FocusNoticeView(
                notice: notice,
                dismiss: { [weak self] in self?.dismiss?() },
                snooze: { [weak self] duration in self?.snooze?(duration) }
            )
        )
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
}

private struct FocusNoticeView: View {
    let notice: FocusNotice
    let dismiss: () -> Void
    let snooze: (Duration) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color(red: 0.99, green: 0.78, blue: 0.33))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                switch notice {
                case let .distraction(target):
                    Text("You need to focus.").font(.system(size: 29, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(target) is on your focus reminder list.").font(.callout)
                    snoozeButtons
                    Button("Dismiss for this visit", action: dismiss)
                case let .inactive(minutes):
                    Text("Still focusing?").font(.system(size: 29, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("No Mac input for \(minutes) \(minutes == 1 ? "minute" : "minutes").")
                        .font(.callout)
                    snoozeButtons
                    Button("I’m here", action: dismiss)
                case .browserAccess:
                    Text("Enable website reminders").font(.system(size: 20, weight: .semibold))
                    Text("Allow Still in Accessibility so it can check the active site during focus.")
                        .font(.callout)
                    HStack {
                        Button("Allow access…") { dismiss(); BrowserLocation.requestAccess() }
                        Button("Later", action: dismiss)
                    }.padding(.top, 5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22).frame(width: 438, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white).colorScheme(.dark)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.14, green: 0.17, blue: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(red: 0.99, green: 0.78, blue: 0.33), lineWidth: 3))
    }

    private var snoozeButtons: some View {
        HStack(spacing: 8) {
            Text("Remind me in").font(.callout)
            Button("1 min") { snooze(.seconds(60)) }
                .accessibilityLabel("Remind me in 1 minute")
            Button("5 min") { snooze(.seconds(300)) }
                .accessibilityLabel("Remind me in 5 minutes")
        }
        .padding(.top, 5)
    }

    private var iconName: String {
        switch notice {
        case .browserAccess:
            return "globe"
        case .inactive:
            return "pause.circle"
        case .distraction:
            return "scope"
        }
    }
}
