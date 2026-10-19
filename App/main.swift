import AppKit

// AppKit entry point. The delegate is kept in a global because
// NSApplication.delegate is a weak reference.
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
