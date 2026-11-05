import AppKit

// What the views use from App/DocklumeApp.swift, left out of the tools because its @main would clash with theirs.
enum DockIcon { @MainActor @discardableResult static func show() -> Bool { false } }
enum AppDelegate { static let mainWindow = "main" }
