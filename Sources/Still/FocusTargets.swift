import AppKit
import Combine

struct FocusApp: Codable, Equatable, Identifiable {
    let id: String
    let name: String
}

struct FocusTargets: Codable, Equatable {
    var enabled: Bool
    var apps: [FocusApp]
    var websites: [String]
    /// Minutes without local Mac input before showing a focus check-in. Zero disables it.
    var idleMinutes: Int

    static let defaultIdleMinutes = 3
    static let supportedIdleMinutes = [0, 1, 3, 5, 10]

    private enum CodingKeys: String, CodingKey {
        case enabled
        case apps
        case websites
        case idleMinutes
    }

    init(enabled: Bool = true, apps: [FocusApp] = [FocusApp(id: "com.valvesoftware.steam", name: "Steam")],
         websites: [String] = FocusTargets.suggestedWebsites, idleMinutes: Int = FocusTargets.defaultIdleMinutes) {
        self.enabled = enabled
        self.apps = apps
        self.websites = websites
        self.idleMinutes = Self.supportedIdleMinutes.contains(idleMinutes) ? idleMinutes : Self.defaultIdleMinutes
    }

    /// Older focus-reminder files do not have `idleMinutes`; retain every existing setting and use 3 minutes.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(enabled: try values.decode(Bool.self, forKey: .enabled),
                  apps: try values.decode([FocusApp].self, forKey: .apps),
                  websites: try values.decode([String].self, forKey: .websites),
                  idleMinutes: try values.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? Self.defaultIdleMinutes)
    }

    static let suggestedWebsites: [String] = {
        guard let file = Bundle.main.url(forResource: "FocusWebsites", withExtension: "txt"),
              let contents = try? String(contentsOf: file, encoding: .utf8) else {
            // A standalone SwiftPM executable can run without the macOS bundle.
            return ["instagram.com", "youtube.com", "x.com", "twitter.com"]
        }
        return contents.split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            return domain(String(line))
        }
    }()

    /// Accept pasted web links, then keep only a normalized DNS name.
    static func domain(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace),
              let components = URLComponents(string: text.contains("://") ? text : "https://" + text),
              ["http", "https"].contains(components.scheme?.lowercased()),
              components.user == nil, components.password == nil,
              var host = components.url?.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        let labels = host.components(separatedBy: ".")
        let valid = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard host.utf8.count <= 253, labels.count > 1,
              labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 && !$0.hasPrefix("-")
                  && !$0.hasSuffix("-") && $0.unicodeScalars.allSatisfy(valid.contains) }) else { return nil }
        return labels.count > 2 && labels.first == "www" ? labels.dropFirst().joined(separator: ".") : host
    }

    func matchedDomain(_ host: String) -> String? {
        websites.first { $0 == host }
    }
}

@MainActor
final class FocusTargetStore: ObservableObject {
    @Published private(set) var targets = FocusTargets()
    @Published private(set) var error: String?
    private let file: URL
    private var readable = true

    init(directory: URL) {
        file = directory.appendingPathComponent("focus-reminders.json")
        do {
            let data = try Data(contentsOf: file)
            targets = try JSONDecoder().decode(FocusTargets.self, from: data)
        } catch let issue as NSError where issue.domain == NSCocoaErrorDomain && issue.code == NSFileReadNoSuchFileError {
            // New installations start with the bundled website list.
        } catch {
            readable = false
            targets = FocusTargets(enabled: false, apps: [], websites: [])
            self.error = "Could not read \(file.lastPathComponent). \(error.localizedDescription)"
        }
    }

    func update(_ change: (inout FocusTargets) -> Void) {
        guard readable else { return }
        var next = targets
        change(&next)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(next).write(to: file, options: .atomic)
            targets = next
            error = nil
        } catch {
            self.error = "Could not save focus reminders. \(error.localizedDescription)"
        }
    }
}
