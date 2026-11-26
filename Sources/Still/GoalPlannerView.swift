import AppKit
import SwiftUI
import StillCore

struct GoalPlannerView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @StoredViewState private var target: Int
    @Environment(\.colorScheme) private var colorScheme

    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _target = StoredViewState(initialValue: model.suggestedGoal)
    }

    var body: some View {
        let palette = Palette.resolved(theme: model.preferences.theme, scheme: colorScheme, colorTheme: model.preferences.colorTheme)
        VStack(alignment: .leading, spacing: 16) {
            Text(model.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline).foregroundStyle(palette.secondary)
            Text("How many deep work sessions today?")
                .font(.system(size: 26, design: .serif)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Stepper(value: $target, in: DailyEvent.goalRange) {
                    Text("\(target) \(target == 1 ? "session" : "sessions")")
                        .font(.title3).monospacedDigit()
                }
            }
            Text(target == 0 ? "Plan a rest day." : "\(target * model.preferences.focusMinutes) minutes at \(model.preferences.focusMinutes) minutes per session.")
                .font(.subheadline).foregroundStyle(palette.secondary)
            Button("View today in Todoist ↗", action: openTodoist).buttonStyle(.link)
            Divider()
            HStack {
                Button("Not now", action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Set goal") {
                    model.setDailyGoal(target)
                    close()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 355).background(palette.background).foregroundStyle(palette.ink)
        .preferredColorScheme(model.preferences.preferredColorScheme())
        .onChange(of: model.todayID) { _, _ in target = model.suggestedGoal }
    }

    private func openTodoist() {
        let appURL = URL(string: "todoist://today")!
        if NSWorkspace.shared.urlForApplication(toOpen: appURL) != nil, NSWorkspace.shared.open(appURL) { return }
        NSWorkspace.shared.open(URL(string: "https://app.todoist.com/app/today")!)
    }
}
