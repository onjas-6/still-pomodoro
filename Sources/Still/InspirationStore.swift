// Created 2026-09-15 · gpt-6-astra · Codex
import AppKit
import Combine
import StillCore

@MainActor
final class InspirationStore: ObservableObject {
    @Published private(set) var current = InspirationCatalog.defaults.phrases[0]
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    let url: URL
    private let preview: Bool
    private var phrases = InspirationCatalog.defaults.phrases
    private var index = 0
    private var reloadPending = false

    init(directory: URL, preview: Bool = false) {
        url = directory.appendingPathComponent("inspiration.json")
        self.preview = preview
        reload()
    }

    func advance() {
        index = (index + 1) % phrases.count
        current = phrases[index]
    }

    // Reopening controls reloads edits, while keeping the current thought stable.
    func reload() {
        guard !preview else { return }
        guard !isLoading else { reloadPending = true; return }
        isLoading = true
        let file = url
        Task {
            let result = await Task.detached(priority: .utility) {
                Result { try Self.read(from: file) }
            }.value
            if reloadPending {
                reloadPending = false
                isLoading = false
                reload()
                return
            }
            switch result {
            case .success(let catalog):
                let selectedID = current.id
                phrases = catalog.phrases
                index = phrases.firstIndex { $0.id == selectedID } ?? 0
                current = phrases[index]
                error = nil
            case .failure:
                // A partial edit must never blank the panel or overwrite the user's file.
                error = "Couldn’t read your phrases. Keeping the last loaded collection."
            }
            isLoading = false
        }
    }

    func edit() {
        guard !preview else { return }
        let file = url
        Task { [self] in
            let result = await Task.detached(priority: .utility) {
                Result {
                    if !FileManager.default.fileExists(atPath: file.path) {
                        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try InspirationCatalog.defaults.encoded().write(to: file, options: .withoutOverwriting)
                    }
                }
            }.value
            switch result {
            case .success:
                NSWorkspace.shared.open([file], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                        configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, failure in
                    if failure != nil { Task { @MainActor in self?.error = "Couldn’t open the local phrase file." } }
                }
            case .failure:
                error = "Couldn’t create the local phrase file."
            }
        }
    }

    private nonisolated static func read(from url: URL) throws -> InspirationCatalog {
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 128 * 1024 + 1) ?? Data()
        return try InspirationCatalog.decode(data)
    }
}
