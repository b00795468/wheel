import Foundation
import os

/// Bundle-derived constants, so the final product name only lives in Info.plist.
enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Pivot"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static let subsystem = Bundle.main.bundleIdentifier ?? "local.pivot.app"
    static let log = Logger(subsystem: subsystem, category: "app")
    static let gestureLog = Logger(subsystem: subsystem, category: "gesture")
}
