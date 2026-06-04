import AppKit
import Foundation

enum ChromeTabServiceError: LocalizedError {
    case chromeNotRunning
    case appleScriptUnavailable
    case appleScriptFailed(String)
    case noTabs
    case noChromeWindow

    var errorDescription: String? {
        switch self {
        case .chromeNotRunning:
            "Google Chrome is not running."
        case .appleScriptUnavailable:
            "Syn could not create the Chrome automation script."
        case .appleScriptFailed(let message):
            "Chrome automation failed: \(message)"
        case .noTabs:
            "No Chrome tabs are available to capture."
        case .noChromeWindow:
            "Syn could not find the activated Chrome window."
        }
    }
}

enum ChromeTabService {
    private static let chromeBundleIdentifier = "com.google.Chrome"
    private static let ownerNames = Set(["Google Chrome"])
    private static let unitSeparator = String(UnicodeScalar(31)!)
    private static let recordSeparator = String(UnicodeScalar(30)!)

    static func isChromeRunning() -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: chromeBundleIdentifier).isEmpty {
            return true
        }

        return NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == chromeBundleIdentifier
                || ownerNames.contains(application.localizedName ?? "")
        }
    }

    static func listTabs() throws -> [ChromeTabTarget] {
        guard isChromeRunning() else {
            throw ChromeTabServiceError.chromeNotRunning
        }

        let output = try runAppleScript(listTabsScript)
        let tabs = parseTabListOutput(output)
        guard !tabs.isEmpty else {
            throw ChromeTabServiceError.noTabs
        }
        return tabs
    }

    static func activate(_ target: ChromeTabTarget) async throws -> ChromeTabTarget {
        guard isChromeRunning() else {
            throw ChromeTabServiceError.chromeNotRunning
        }

        let script = activateTabScript(target: target)
        let output = try runAppleScript(script)
        let activated = parseActivatedTabOutput(output, fallback: target)

        try? await Task.sleep(nanoseconds: 250_000_000)
        guard let windowID = frontChromeWindowID() else {
            throw ChromeTabServiceError.noChromeWindow
        }

        var resolved = activated
        resolved.windowID = windowID
        return resolved
    }

    static func fixtureTabs() -> [ChromeTabTarget] {
        [
            ChromeTabTarget(
                windowIndex: 1,
                tabIndex: 1,
                title: "Atlas Pull Request",
                url: "https://github.com/example/atlas/pull/42",
                windowID: 4242
            ),
            ChromeTabTarget(
                windowIndex: 1,
                tabIndex: 2,
                title: "Syn Product Spec",
                url: "https://docs.example.test/syn",
                windowID: 4242
            )
        ]
    }

    static func parseTabListOutput(_ output: String) -> [ChromeTabTarget] {
        output
            .split(separator: Character(recordSeparator), omittingEmptySubsequences: true)
            .compactMap { row -> ChromeTabTarget? in
                let fields = row.split(separator: Character(unitSeparator), omittingEmptySubsequences: false)
                guard fields.count >= 4,
                      let windowIndex = Int(fields[0]),
                      let tabIndex = Int(fields[1]) else {
                    return nil
                }

                return ChromeTabTarget(
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    title: String(fields[2]),
                    url: String(fields[3]),
                    windowID: nil
                )
            }
    }

    static func encodedFixtureOutput() -> String {
        fixtureTabs()
            .map { tab in
                [
                    String(tab.windowIndex),
                    String(tab.tabIndex),
                    tab.title,
                    tab.url
                ].joined(separator: unitSeparator)
            }
            .joined(separator: recordSeparator)
    }

    private static func parseActivatedTabOutput(_ output: String, fallback: ChromeTabTarget) -> ChromeTabTarget {
        let fields = output.split(separator: Character(unitSeparator), omittingEmptySubsequences: false)
        guard fields.count >= 4,
              let windowIndex = Int(fields[0]),
              let tabIndex = Int(fields[1]) else {
            return fallback
        }

        return ChromeTabTarget(
            windowIndex: windowIndex,
            tabIndex: tabIndex,
            title: String(fields[2]),
            url: String(fields[3]),
            windowID: fallback.windowID
        )
    }

    private static func frontChromeWindowID() -> CGWindowID? {
        let runningPIDs = Set(NSRunningApplication
            .runningApplications(withBundleIdentifier: chromeBundleIdentifier)
            .map(\.processIdentifier))
        let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  runningPIDs.contains(ownerPID),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  ownerNames.contains(ownerName),
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else {
                continue
            }

            let width = bounds["Width"] as? CGFloat ?? 0
            let height = bounds["Height"] as? CGFloat ?? 0
            guard width > 80, height > 60 else {
                continue
            }

            return CGWindowID(number)
        }

        return nil
    }

    private static func runAppleScript(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw ChromeTabServiceError.appleScriptUnavailable
        }

        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String
                ?? error.description
            throw ChromeTabServiceError.appleScriptFailed(message)
        }

        return descriptor.stringValue ?? ""
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    private static var listTabsScript: String {
        """
        set unitSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        set output to ""

        tell application "Google Chrome"
            repeat with windowIndex from 1 to count of windows
                set chromeWindow to window windowIndex
                repeat with tabIndex from 1 to count of tabs of chromeWindow
                    set chromeTab to tab tabIndex of chromeWindow
                    set output to output & windowIndex & unitSeparator & tabIndex & unitSeparator & my cleanText(title of chromeTab) & unitSeparator & my cleanText(URL of chromeTab) & recordSeparator
                end repeat
            end repeat
        end tell

        return output

        on cleanText(rawText)
            set oldDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to {ASCII character 9, ASCII character 10, ASCII character 13, ASCII character 30, ASCII character 31}
            set parts to text items of (rawText as text)
            set AppleScript's text item delimiters to " "
            set cleaned to parts as text
            set AppleScript's text item delimiters to oldDelimiters
            return cleaned
        end cleanText
        """
    }

    private static func activateTabScript(target: ChromeTabTarget) -> String {
        let wantedURL = appleScriptStringLiteral(target.url)
        return """
        set unitSeparator to ASCII character 31
        set wantedURL to \(wantedURL)
        set fallbackWindowIndex to \(max(target.windowIndex, 1))
        set fallbackTabIndex to \(max(target.tabIndex, 1))

        tell application "Google Chrome"
            set windowCount to count of windows
            if windowCount is 0 then error "No Chrome windows are available."

            set foundWindowIndex to 0
            set foundTabIndex to 0

            repeat with windowIndex from 1 to windowCount
                set chromeWindow to window windowIndex
                repeat with tabIndex from 1 to count of tabs of chromeWindow
                    if (URL of tab tabIndex of chromeWindow as text) is wantedURL then
                        set foundWindowIndex to windowIndex
                        set foundTabIndex to tabIndex
                        exit repeat
                    end if
                end repeat
                if foundWindowIndex is not 0 then exit repeat
            end repeat

            if foundWindowIndex is 0 then
                set foundWindowIndex to fallbackWindowIndex
                if foundWindowIndex > windowCount then set foundWindowIndex to 1
                set fallbackWindow to window foundWindowIndex
                set fallbackTabCount to count of tabs of fallbackWindow
                if fallbackTabCount is 0 then error "The selected Chrome window has no tabs."
                set foundTabIndex to fallbackTabIndex
                if foundTabIndex > fallbackTabCount then set foundTabIndex to 1
            end if

            set targetWindow to window foundWindowIndex
            set active tab index of targetWindow to foundTabIndex
            set index of targetWindow to 1
            activate

            set activeTab to active tab of front window
            return foundWindowIndex & unitSeparator & foundTabIndex & unitSeparator & my cleanText(title of activeTab) & unitSeparator & my cleanText(URL of activeTab)
        end tell

        on cleanText(rawText)
            set oldDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to {ASCII character 9, ASCII character 10, ASCII character 13, ASCII character 30, ASCII character 31}
            set parts to text items of (rawText as text)
            set AppleScript's text item delimiters to " "
            set cleaned to parts as text
            set AppleScript's text item delimiters to oldDelimiters
            return cleaned
        end cleanText
        """
    }
}
