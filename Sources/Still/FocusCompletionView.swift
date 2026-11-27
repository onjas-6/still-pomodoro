// Created 2026-11-25 · Codex
import SwiftUI

/// A local, actionable focus-completion cue. It stays visible independently of
/// the system notification sound, so completing a session remains apparent when
/// the Mac or Still's chime is muted.
struct FocusCompletionView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @StoredViewState private var glowing = false

    private var isDark: Bool { colorScheme == .dark }
    private var fill: Color { isDark ? Color(red: 0.08, green: 0.16, blue: 0.11) : Color(red: 0.91, green: 0.98, blue: 0.92) }
    private var primary: Color { isDark ? Color(red: 0.67, green: 0.95, blue: 0.73) : Color(red: 0.08, green: 0.29, blue: 0.17) }
    private var secondary: Color { isDark ? Color.white.opacity(0.76) : Color.black.opacity(0.62) }
    private var accent: Color { isDark ? Color(red: 0.36, green: 0.82, blue: 0.49) : Color(red: 0.13, green: 0.38, blue: 0.27) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                Text("Focus complete")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
            }
            .foregroundStyle(primary)

            Text("\(Int(model.timer.duration / 60)) minutes completed")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(secondary)

            HStack(spacing: 10) {
                Button("Not now") { model.dismissFocusCompletionAlert() }
                    .buttonStyle(.borderless)
                Spacer()
                Button(model.focusCompletionBreakButtonTitle) { model.primaryAction() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
            .controlSize(.regular)
        }
        .padding(24)
        .frame(width: 400)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(accent.opacity(glowing ? 0.92 : 0.35), lineWidth: glowing ? 4 : 2)
                }
                .shadow(color: accent.opacity(glowing ? 0.42 : 0.16), radius: glowing ? 25 : 12)
        }
        .foregroundStyle(primary)
        .task {
            // Glow in short bursts; the panel stays until dismissed, which can be a long time.
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { glowing = true }
                try? await Task.sleep(for: .seconds(10))
                withAnimation(.easeOut(duration: 0.5)) { glowing = false }
                try? await Task.sleep(for: .seconds(50))
            }
        }
        .preferredColorScheme(model.preferences.preferredColorScheme())
        .accessibilityElement(children: .contain)
    }
}
