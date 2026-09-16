// Created 2026-09-15 · gpt-6-astra · Codex
import SwiftUI

struct InspirationView: View {
    @ObservedObject var store: InspirationStore
    let palette: Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 9) {
            Rectangle().fill(palette.ink.opacity(0.075)).frame(height: 0.5)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.current.source ?? "A LITTLE PERSPECTIVE")
                        .font(.system(size: 8, weight: .medium)).tracking(0.8)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                    Text(store.current.text)
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .lineSpacing(3).multilineTextAlignment(.leading)
                        .foregroundStyle(palette.ink.opacity(0.85))
                        .lineLimit(3).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(store.current.id)
                        .transition(.opacity)
                }
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { store.advance() }
                } label: {
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(palette.ink.opacity(0.035), in: Circle())
                }
                .buttonStyle(.plain).foregroundStyle(palette.secondary)
                .help("Another thought").accessibilityLabel("Another thought")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct InspirationPreferences: View {
    @ObservedObject var store: InspirationStore
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Small reminders, only when you expand.")
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
                Spacer()
                Button("Edit phrases…") { store.edit() }.buttonStyle(.link).font(.system(size: 11))
            }
            Text("Save your edits, then reopen the timer to load them.")
                .font(.system(size: 10)).foregroundStyle(palette.secondary)
            if let error = store.error { Text(error).font(.system(size: 10)).foregroundStyle(.orange) }
        }
    }
}
