// Created 2026-09-18 · gpt-6-astra · Codex
import SwiftUI

struct RestReminderView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StoredViewState private var glowing = false
    @StoredViewState private var breathing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                Text("TIME TO REST").tracking(2.2)
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color(red: 0.52, green: 0.27, blue: 0.10))
            Text(model.preferences.restMessage)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text("保护明天的工作效率，才有余力兑现好奇心和野心。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("5 分钟后再提醒") { model.snoozeRestReminder() }
                    .controlSize(.regular)
            }
        }
        .padding(26)
        .frame(width: 470)
        .frame(minHeight: 200)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 1, green: 0.96, blue: 0.86))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.orange.opacity(glowing ? 1.0 : 0.25), lineWidth: glowing ? 5 : 2)
                }
                .shadow(color: .orange.opacity(glowing ? 0.5 : 0.12), radius: glowing ? 30 : 12)
        }
        .foregroundStyle(Color(red: 0.22, green: 0.17, blue: 0.12))
        .scaleEffect(breathing ? 1.03 : 1.0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { glowing = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}
