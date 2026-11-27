import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

struct FocusTargetPreferences: View {
    @ObservedObject var store: FocusTargetStore
    let palette: Palette
    @StoredViewState private var draft = ""
    @StoredViewState private var validation: String?
    @StoredViewState private var hasAccess = AXIsProcessTrusted()
    @StoredViewState private var showsWebsites = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Enable focus reminders", isOn: Binding(
                get: { store.targets.enabled }, set: { enabled in store.update { $0.enabled = enabled } }))
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            inactivity
            separator
            apps
            separator
            websites
        }
        .onAppear { hasAccess = AXIsProcessTrusted() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccess = AXIsProcessTrusted()
        }
    }

    private var inactivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreferenceSubheading("Inactivity check-in")
            Picker("Check in after no input for", selection: Binding(
                get: { store.targets.idleMinutes },
                set: { minutes in store.update { $0.idleMinutes = minutes } }
            )) {
                ForEach(FocusTargets.supportedIdleMinutes, id: \.self) { minutes in
                    Text(minutes == 0 ? "Off" : "\(minutes) min").tag(minutes)
                }
            }
            .fixedSize()
            note("Still plays a sound and asks if you are still focusing. Choose a longer interval for reading.")
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                PreferenceSubheading("Distracting apps")
                Spacer()
                Button("Choose app…", action: chooseApp)
            }
            if store.targets.apps.isEmpty { note("No apps yet.") }
            ForEach(store.targets.apps) { app in
                row(app.name) { store.update { $0.apps.removeAll { $0.id == app.id } } }
            }
        }
    }

    private var websites: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreferenceSubheading("Distracting websites")
            HStack {
                TextField("example.com", text: $draft).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Website to add").onSubmit(addWebsite)
                Button("Add website", action: addWebsite)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let validation { note(validation) }
            DisclosureGroup(isExpanded: $showsWebsites) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.targets.websites, id: \.self) { site in
                        row(site) { store.update { $0.websites.removeAll { $0 == site } } }
                    }
                }
                .padding(.top, 4)
            } label: {
                Text(websiteSummary).font(.system(size: 12))
            }
            note("Each entry includes its www address. Add other subdomains individually.")
            HStack {
                Text(hasAccess ? "Website access is enabled." : "Website reminders need Accessibility access.")
                    .font(.system(size: 10)).foregroundStyle(hasAccess ? palette.secondary : palette.ink)
                Spacer()
                if !hasAccess {
                    Button("Allow access…") { BrowserLocation.requestAccess() }.buttonStyle(.link).font(.system(size: 11))
                }
            }
        }
    }

    private var websiteSummary: String {
        let count = store.targets.websites.count
        return showsWebsites ? "Hide list" : count == 1 ? "Show 1 website" : "Show \(count) websites"
    }

    private var separator: some View {
        Rectangle().fill(palette.ink.opacity(0.07)).frame(height: 1)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
