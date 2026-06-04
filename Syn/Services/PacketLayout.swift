import Foundation

enum PacketLayout {
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("Syn", isDirectory: true)
    }

    static func packetFolderURL(title: String, createdAt: Date = .now) -> URL {
        let day = dayFormatter.string(from: createdAt)
        let timestamp = timestampFormatter.string(from: createdAt)
        let slug = slugify(title)

        return defaultRoot
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent("\(slug)-\(timestamp)", isDirectory: true)
    }

    static func zipURL(for folderURL: URL) -> URL {
        folderURL
            .deletingLastPathComponent()
            .appendingPathComponent(folderURL.lastPathComponent)
            .appendingPathExtension("zip")
    }

    static func rawZipURL(for folderURL: URL) -> URL {
        folderURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(folderURL.lastPathComponent)-with-raw")
            .appendingPathExtension("zip")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH-mm-ss"
        return formatter
    }()

    private static func slugify(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let normalized = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        let scalars = normalized.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }

        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")

        return collapsed.isEmpty ? "recording" : collapsed
    }
}
