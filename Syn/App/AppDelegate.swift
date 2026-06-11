import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if FixtureProcessingRunner.isRequested {
            NSApp.setActivationPolicy(.prohibited)
            Task { @MainActor in
                let status = await FixtureProcessingRunner.runFromCommandLine()
                exit(status)
            }
            return
        }

        NSApp.setActivationPolicy(.accessory)
        GlobalHotkeyService.shared.start()
        WebElementBridge.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkeyService.shared.stop()
        WebElementBridge.shared.stop()
    }
}
