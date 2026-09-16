// Created 2026-09-15 · gpt-6-astra · Codex
import SwiftUI

/// Keep partially typed values in the native editor until Return or focus loss.
struct DurationField: NSViewRepresentable {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: String(value))
        field.bezelStyle = .roundedBezel
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.alignment = .right
        field.controlSize = .small
        field.setAccessibilityLabel(title + " in minutes")
        field.toolTip = "\(range.lowerBound)–\(range.upperBound) minutes · Return to save"
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.commit(_:))
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        let text = String(value)
        if field.currentEditor() == nil && field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DurationField
        init(_ parent: DurationField) { self.parent = parent }

        @objc func commit(_ field: NSTextField) {
            let parsed = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? parent.value
            let accepted = min(parent.range.upperBound, max(parent.range.lowerBound, parsed))
            field.stringValue = String(accepted)
            if accepted != parent.value { parent.value = accepted }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField { commit(field) }
        }
    }
}
