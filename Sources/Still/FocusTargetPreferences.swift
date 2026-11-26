import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

struct FocusTargetPreferences: View {
    @ObservedObject var store: FocusTargetStore
    @StoredViewState private var draft = ""
    @StoredViewState private var validation: String?
    @StoredViewState private var hasAccess = AXIsProcessTrusted()

    var body: some View {
        Toggle("Enable focus reminders", isOn: Binding(
            get: { store.targets.enabled }, set: { enabled in store.update { $0.enabled = enabled } }))
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mac inactivity during focus", selection: Binding(
                get: { store.targets.idleMinutes },
                set: { minutes in store.update { $0.idleMinutes = minutes } }
            )) {
                ForEach(FocusTargets.supportedIdleMinutes, id: \.self) { minutes in
                    Text(minutes == 0 ? "Off" : "\(minutes) min").tag(minutes)
                }
            }
            Text("After this much time without input, Still checks in with a sound and a panel. Choose a longer interval for reading.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Apps").font(.headline)
                Spacer()
                Button("Choose app…", action: chooseApp)
            }
            ForEach(store.targets.apps) { app in
                row(app.name) { store.update { $0.apps.removeAll { $0.id == app.id } } }
            }
            Text("Websites").font(.headline).padding(.top, 6)
            ForEach(store.targets.websites, id: \.self) { site in
                row(site) { store.update { $0.websites.removeAll { $0 == site } } }
            }
            HStack {
                TextField("example.com", text: $draft).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Website to add").onSubmit(addWebsite)
                Button("Add website", action: addWebsite)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let validation { Text(validation).font(.caption).foregroundStyle(.secondary) }
            Text("Each entry includes its www address. Add other subdomains individually.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(hasAccess ? "Website access is enabled." : "Website reminders need Accessibility access.")
                    .font(.caption)
                Spacer()
                if !hasAccess {
                    Button("Allow access…") { BrowserLocation.requestAccess() }.buttonStyle(.link)
                }
            }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .onAppear { hasAccess = AXIsProcessTrusted() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccess = AXIsProcessTrusted()
        }
    }

    private func row(_ name: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(name).font(.callout).lineLimit(1)
            Spacer()
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).accessibilityLabel("Remove " + name)
        }
    }

    private func addWebsite() {
        guard let host = FocusTargets.domain(draft) else {
            validation = "Enter a domain name or an http or https link."
            return
        }
        if !store.targets.websites.contains(host) { store.update { $0.websites.append(host) } }
        if store.error == nil { draft = ""; validation = nil }
    }

    private func chooseApp() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.applicationBundle]
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.prompt = "Add app"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        guard let id = Bundle(url: url)?.bundleIdentifier else {
            validation = "This app has no macOS bundle identifier."
            return
        }
        if store.targets.apps.contains(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) { return }
        let name = url.deletingPathExtension().lastPathComponent
        store.update { $0.apps.append(FocusApp(id: id, name: name)) }
        validation = nil
    }
}
