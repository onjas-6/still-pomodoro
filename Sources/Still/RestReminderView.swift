// Created 2026-09-18 · gpt-6-astra · Codex
import SwiftUI

struct RestReminderView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StoredViewState private var glowing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                Text("TIME TO REST").tracking(1.8)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(red: 0.52, green: 0.27, blue: 0.10))
            Text(model.preferences.restMessage)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text("保护明天的工作效率，才有余力兑现好奇心和野心。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("10 分钟后再提醒") { model.snoozeRestReminder() }
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 380)
        .frame(minHeight: 155)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 1, green: 0.96, blue: 0.86))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.orange.opacity(glowing ? 0.92 : 0.22), lineWidth: glowing ? 3 : 1)
                }
                .shadow(color: .orange.opacity(glowing ? 0.35 : 0.09), radius: glowing ? 22 : 9)
        }
        .foregroundStyle(Color(red: 0.22, green: 0.17, blue: 0.12))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glowing = true }
        }
    }
}
