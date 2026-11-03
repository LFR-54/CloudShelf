import SwiftUI

/// Release notes on a timeline, after the RaiDrive page: years on the left, releases with their categories on the right.
struct NotesDialog: View {
    @Environment(\.dialogSpace) private var space
    @Environment(DriveStore.self) private var store
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var category: Release.Category?
    @State private var folded: Set<Int> = []

    var body: some View {
        @Bindable var preferences = store.preferences
        ModalSurface(width: 800) {
            VStack(spacing: 0) {
                ModalHead(title: "Notes de version", subtitle: "Nouveautés, améliorations et corrections de chaque version de CloudShelf.") {
                    app.overlay = nil
                }
                HStack(spacing: 10) {
                    SearchField(text: $query, placeholder: "Rechercher une version ou une note", width: nil, height: 30)
                    SegmentedControl(selection: $category, options: [nil] + Release.Category.allCases.map(Optional.some)) {
                        $0?.filter ?? "Tout"
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 14)
                ScrollView {
                    list
                        .padding(.top, 22)
                        .padding(.trailing, 26)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: min(452, max(240, space.height - 300)))
                .card(fill: Theme.cardSolid)
                .padding(.horizontal, 22)
                HStack(spacing: 10) {
                    Toggle("Afficher après chaque mise à jour", isOn: $preferences.showNotesAfterUpdate)
                        .toggleStyle(.checkbox)
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
        .onAppear { store.preferences.notesSeenVersion = Preferences.appVersion }
    }

    private var shown: [(release: Release, sections: [(Release.Category, [Release.Note])])] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        return Release.all.compactMap { release in
            let versionHit = !text.isEmpty && release.version.lowercased().contains(text)
            let sections = Release.Category.allCases
                .filter { category == nil || category == $0 }
                .map { ($0, (release.notes[$0] ?? []).filter { text.isEmpty || versionHit || $0.text.lowercased().contains(text) }) }
                .filter { !$0.1.isEmpty }
            return sections.isEmpty ? nil : (release, sections)
        }
    }

    @ViewBuilder private var list: some View {
        let shown = shown
        if shown.isEmpty {
            Text(query.isEmpty ? "Aucune note dans cette catégorie." : "Aucune note ne correspond à « \(query.trimmingCharacters(in: .whitespaces)) ».")
                .foregroundStyle(Theme.text2)
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
                .padding(.leading, 26)
        } else {
            let years = Array(Set(shown.map(\.release.year))).sorted(by: >)
            VStack(alignment: .leading, spacing: 26) {
                ForEach(years, id: \.self) { year in
                    let items = shown.filter { $0.release.year == year }
                    yearBlock(year, items)
                }
            }
        }
    }

    private func yearBlock(_ year: Int, _ items: [(release: Release, sections: [(Release.Category, [Release.Note])])]) -> some View {
        let isFolded = folded.contains(year)
        return HStack(alignment: .top, spacing: 18) {
            Button {
                if isFolded { folded.remove(year) } else { folded.insert(year) }
            } label: {
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 3) {
                        Text(String(year))
                            .font(.system(size: 23, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text3)
                            .rotationEffect(.degrees(isFolded ? -90 : 0))
                    }
                    Text(Format.plural(items.count, "version"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                }
                .frame(width: 104, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isFolded ? "replié" : "déplié")
            VStack(alignment: .leading, spacing: 0) {
                if isFolded {
                    Text(items.map(\.release.version).joined(separator: " · "))
                        .foregroundStyle(Theme.text3)
                        .padding(.top, 2)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.release.id) { index, item in
                        if index > 0 {
                            Hairline()
                                .padding(.top, 22)
                                .padding(.bottom, 20)
                        }
                        ReleaseView(release: item.release, sections: item.sections)
                    }
                }
            }
            .padding(.leading, 24)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                Rectangle().fill(Theme.separator).frame(width: 2).frame(maxHeight: .infinity)
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(Theme.text3)
                    .frame(width: 12, height: 12)
                    .background(Circle().fill(Theme.cardSolid).padding(-3))
                    .offset(x: -5, y: 5)
            }
        }
    }
}

private struct ReleaseView: View {
    let release: Release
    let sections: [(Release.Category, [Release.Note])]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(release.version)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.21)
                Text(release.date)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                if release.latest { ReleaseBadge(text: "Dernière", color: Theme.accent) }
                if release.security { ReleaseBadge(text: "Sécurité", color: Theme.security) }
                Spacer(minLength: 8)
                Text(release.engine)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
            }
            ForEach(sections, id: \.0) { category, notes in
                HStack(spacing: 8) {
                    Circle().fill(color(category)).frame(width: 9, height: 9)
                    Text(category.title).font(.system(size: 13.5, weight: .bold))
                }
                .padding(.top, 13)
                .padding(.bottom, 4)
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("•")
                            .frame(width: 35, alignment: .center)
                            .padding(.leading, 4)
                            .padding(.trailing, -4)
                        if note.security {
                            ReleaseBadge(text: "Sécurité", color: Theme.security)
                                .padding(.trailing, 6)
                        }
                        Text(note.text)
                            .fontWeight(note.bold ? .semibold : .regular)
                            .lineSpacing(13 * 0.25)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func color(_ category: Release.Category) -> Color {
        switch category {
        case .new: Theme.green
        case .improved: Theme.teal
        case .fixed: Theme.gray
        }
    }
}

private struct ReleaseBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
    }
}
