import Foundation

enum CaptureMode: String, CaseIterable, Codable, Identifiable {
    case screen
    case allScreens
    case chromeTab
    case activeWindowFollow
    case selectedWindow
    case region
    case smartRegion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screen:
            "Screen"
        case .allScreens:
            "All Screens"
        case .chromeTab:
            "Chrome Tab"
        case .activeWindowFollow:
            "Active Window"
        case .selectedWindow:
            "Select Window"
        case .region:
            "Region"
        case .smartRegion:
            "Smart Region"
        }
    }

    var detail: String {
        switch self {
        case .screen:
            "Capture one display."
        case .allScreens:
            "Capture every display."
        case .chromeTab:
            "Capture one Chrome tab."
        case .activeWindowFollow:
            "Follow the frontmost window."
        case .selectedWindow:
            "Capture one chosen window."
        case .region:
            "Draw a fixed rectangle."
        case .smartRegion:
            "Follow the cursor in a region."
        }
    }

    var systemImage: String {
        switch self {
        case .screen:
            "display"
        case .allScreens:
            "rectangle.3.group"
        case .chromeTab:
            "globe"
        case .activeWindowFollow:
            "macwindow.on.rectangle"
        case .selectedWindow:
            "macwindow"
        case .region:
            "selection.pin.in.out"
        case .smartRegion:
            "scope"
        }
    }
}
