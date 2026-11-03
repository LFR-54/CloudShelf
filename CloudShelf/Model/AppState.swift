import Foundation

/// What the window shows: the page, the dialog on top of it and the toast.
@MainActor @Observable
final class AppState {
    enum Page: Hashable {
        case drives
        case activity
        case settings
        case drive(String)
    }

    enum Overlay: Equatable {
        case add(provider: String)
        case edit(drive: String)
        case log(drive: String)
        case options(drive: String)
        case alert(Alert)
        case notes
        case about
    }

    struct Alert: Equatable {
        let id = UUID()
        let title: String
        let message: String
        let confirm: String
        var destructive = false
        let action: @MainActor () -> Void

        static func == (lhs: Alert, rhs: Alert) -> Bool { lhs.id == rhs.id }
    }

    struct Toast: Equatable {
        let id = UUID()
        let message: String
        let warning: Bool
    }

    var page = Page.drives {
        didSet { renaming = nil }
    }
    var overlay: Overlay?
    /// Set once the user has agreed to quit with uploads in progress, so ⌘Q does not ask again.
    var quitConfirmed = false
    private(set) var toast: Toast?
    var query = ""
    /// The drive whose name is being edited in the list.
    var renaming: String?
    /// Bumped to put the focus in the name field of the drive page.
    var nameFieldRequest = 0

    func show(_ message: String, warning: Bool = false) {
        let toast = Toast(message: message, warning: warning)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            if self.toast == toast { self.toast = nil }
        }
    }

    func confirm(_ title: String, message: String, confirm: String, destructive: Bool = false, action: @escaping @MainActor () -> Void) {
        overlay = .alert(Alert(title: title, message: message, confirm: confirm, destructive: destructive, action: action))
    }
}
