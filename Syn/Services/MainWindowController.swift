import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?

    private init() {}

    func show(appState: AppState) {
        guard !FixtureProcessingRunner.isRequested else {
            return
        }

        if window == nil {
            let rootView = ContentView().environmentObject(appState)
            let hostingView = NSHostingView(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Syn"
            window.contentView = hostingView
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            self.window = window
            // Center only on first creation; re-centering on every show makes
            // the window jump displays on multi-monitor setups.
            window.center()
        }

        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        NSLog("Syn main window requested")
    }
}
