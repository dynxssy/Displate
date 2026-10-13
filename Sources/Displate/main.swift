import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    if PreviewRenderer.renderIfRequested() { exit(0) }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
