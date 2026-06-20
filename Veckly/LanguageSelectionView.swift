import SwiftUI

struct LanguageSelectionView: View {
    @Environment(AppLanguageStore.self) private var languageStore

    var body: some View {
        List(AppLanguage.allCases) { language in
            Button {
                languageStore.select(language)
            } label: {
                HStack {
                    Text(language.titleKey)
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    Spacer()
                    if languageStore.selection == language {
                        Image(systemName: "checkmark")
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("languageOption.\(language.rawValue)")
        }
        .navigationTitle(L10n.string("app.language"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension AppLanguage {
    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "language.system"
        case .swedish: "language.swedish"
        case .english: "language.english"
        }
    }
}
