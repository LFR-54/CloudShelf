import SwiftUI

/// The drive's rclone log, filtered by level and refreshed while open.
struct LogDialog: View {
    @Environment(\.dialogSpace) private var space
    enum Level: String, CaseIterable {
        case all = "Tout"
        case warnings = "Avertissements"
        case errors = "Erreurs"

        func includes(_ level: String) -> Bool {
            switch self {
            case .all: true
            case .warnings: level != "INFO" && level != "DEBUG"
            case .errors: level == "ERROR" || level == "CRITICAL"
            }
        }
    }

    @Environment(AppState.self) private var app
    let drive: Drive
    @State private var level = Level.all
    @State private var lines: [RcloneLog.Line] = []

    var body: some View {
        ModalSurface(width: 780) {
            VStack(spacing: 0) {
                ModalHead(title: "Journal de \(drive.name)",
                          subtitle: "Sortie de rclone, niveau INFO. Les mots de passe et jetons sont masqués.", showsLogo: false) {
                    app.overlay = nil
                }
                HStack(spacing: 10) {
                    SegmentedControl(selection: $level, options: Level.allCases, title: \.rawValue)
                    Spacer()
                    Button("Copier", action: copy)
                        .buttonStyle(PushButtonStyle())
                    Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([drive.logFile]) }
                        .buttonStyle(PushButtonStyle())
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if visible.isEmpty {
                            Text(lines.isEmpty ? "Le journal est vide : le lecteur n'a pas encore été monté." : "Aucune ligne à ce niveau.")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.text2)
                                .padding(.leading, 156)
                                .padding(.vertical, 3)
                        }
                        ForEach(visible) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(line.time).foregroundStyle(Theme.text3).frame(width: 70, alignment: .leading)
                                Text(line.level).fontWeight(.semibold).foregroundStyle(color(line.level)).frame(width: 62, alignment: .leading)
                                Text(line.message).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }
                            .font(.system(size: 11.5, design: .monospaced))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 3)
                            .id(line.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .frame(height: min(380, max(200, space.height - 280)))
                .card()
                .padding(.horizontal, 22)
                HStack {
                    Spacer()
                    Button("Fermer") { app.overlay = nil }
                        .buttonStyle(PushButtonStyle.largePrimary)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 16)
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
        }
        .task {
            while !Task.isCancelled {
                let url = drive.logFile
                let fresh = await Task.detached { RcloneLog.lines(at: url) }.value
                if fresh != lines { lines = fresh }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var visible: [RcloneLog.Line] { lines.filter { level.includes($0.level) } }

    private func color(_ level: String) -> Color {
        switch level {
        case "NOTICE", "WARNING": Theme.orange
        case "ERROR", "CRITICAL": Theme.red
        default: Theme.text2
        }
    }

    private func copy() {
        let text = visible.map { "\($0.time) \($0.level) \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.show("\(Format.plural(visible.count, "ligne")) copiée\(visible.count > 1 ? "s" : "")")
    }
}
