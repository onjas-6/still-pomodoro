// Created 2026-09-15 · gpt-6-astra · Codex
import SwiftUI

struct AppearanceOptions: View {
    @ObservedObject var model: AppModel
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Theme color").font(.system(size: 12))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(ColorTheme.all) { theme in
                    let selected = model.preferences.colorTheme == theme.id
                    Button { model.preferences.colorTheme = theme.id } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Color(hex: theme.swatch)).frame(width: 11, height: 11)
                            Text(theme.name).font(.system(size: 10))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).frame(height: 30)
                        .background(palette.ink.opacity(selected ? 0.09 : 0.025), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.ink.opacity(selected ? 0.30 : 0), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.name + " color theme")
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                }
            }
            Picker("Edges", selection: $model.preferences.edgeStyle) {
                Text("Glass").tag("glass")
                Text("Diffuse").tag("diffuse")
            }.pickerStyle(.segmented)
            Text(model.preferences.edgeStyle == "diffuse"
                 ? "A soft color wash fades into your desktop."
                 : "Frosted glass with a defined, rounded edge.")
                .font(.system(size: 10)).foregroundStyle(palette.secondary)
        }
    }
}
