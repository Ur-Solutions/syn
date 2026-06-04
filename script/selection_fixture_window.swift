import AppKit
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 80, y: 80, width: 1200, height: 800)
let size = NSSize(width: 560, height: 340)
let origin = NSPoint(
    x: visibleFrame.midX - size.width / 2,
    y: visibleFrame.midY - size.height / 2
)

let window = NSWindow(
    contentRect: NSRect(origin: origin, size: size),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "Syn Window Selection Fixture Target"
window.isReleasedWhenClosed = false

let label = NSTextField(labelWithString: "Syn Window Selection Fixture Target")
label.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
label.alignment = .center
label.frame = NSRect(x: 28, y: 142, width: size.width - 56, height: 44)

let detail = NSTextField(labelWithString: "This external window gives Syn a stable selection target for overlay verification.")
detail.font = NSFont.systemFont(ofSize: 14)
detail.textColor = .secondaryLabelColor
detail.alignment = .center
detail.frame = NSRect(x: 28, y: 108, width: size.width - 56, height: 28)

let content = NSView(frame: NSRect(origin: .zero, size: size))
content.wantsLayer = true
content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
content.addSubview(label)
content.addSubview(detail)
window.contentView = content
window.orderFrontRegardless()
app.activate(ignoringOtherApps: true)

DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
    app.terminate(nil)
}

app.run()
