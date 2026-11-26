import Foundation

enum JournalLocation {
    static let mySpace = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/MySpace", isDirectory: true)
    static let mySpaceJournal = mySpace.appendingPathComponent("Life/Still/Deep Work.md")
    static let legacyJournal = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Still-sessions.md")

    /// Keep the Desktop path in preferences. On the Mac mini the directory is a
    /// Finder alias, while on the primary Mac it can be an ordinary folder or symlink.
    static func resolved(_ url: URL, mySpaceRoot: URL = mySpace) throws -> URL {
        let prefix = mySpaceRoot.path + "/"
        guard url.path.hasPrefix(prefix) else { return url }
        let values = try mySpaceRoot.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])
        let root: URL
        if values.isAliasFile == true && values.isSymbolicLink != true {
            root = try URL(resolvingAliasFileAt: mySpaceRoot, options: [.withoutUI, .withoutMounting])
        } else {
            root = mySpaceRoot.resolvingSymlinksInPath()
        }
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return root.appendingPathComponent(String(url.path.dropFirst(prefix.count)))
    }
}
