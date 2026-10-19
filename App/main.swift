import AppKit

// AppKit entry point. Top-level code is not main-actor isolated in Swift 6,
// but it does run on the main thread. app.run() never returns, so the
// delegate (a weak reference on NSApplication) stays alive.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.run()
}
