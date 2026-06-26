import Foundation

struct SelectedWindowTarget: Codable, Sendable {
    var windowID: UInt32
    var ownerPID: Int32?
    var appName: String?
    var windowTitle: String?
    var bounds: CodableRect?
}

struct AppPreferences: Codable {
    var lastCaptureMode: CaptureMode?
    var lastRegion: RegionSelection?
    var lastSelectedWindowID: UInt32?
    var lastSelectedWindowTarget: SelectedWindowTarget?
    var lastChromeTabTarget: ChromeTabTarget?
    var lastDisplayID: UInt32?
    var defaultPromptProfile: AgentPromptProfile?
    var projectContextFolderPath: String?
    var hasCompletedInitialSetup: Bool?
    var setupTestSucceededAt: Date?
}

enum AppPreferencesStore {
    private static var preferencesURL: URL {
        if let override = ProcessInfo.processInfo.environment["SYN_PREFERENCES_PATH"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Syn", isDirectory: true)
            .appendingPathComponent("preferences.json")
    }

    static func load() -> AppPreferences {
        guard let data = try? Data(contentsOf: preferencesURL),
              let preferences = try? JSONDecoder.synDecoder.decode(AppPreferences.self, from: data) else {
            return AppPreferences()
        }

        return preferences
    }

    static func save(_ preferences: AppPreferences) {
        do {
            let url = preferencesURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.synEncoder.encode(preferences)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Syn failed to save preferences: \(error.localizedDescription)")
        }
    }
}
