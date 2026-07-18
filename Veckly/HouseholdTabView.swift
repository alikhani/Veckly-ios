import SwiftUI

struct HouseholdTabView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppLanguageStore.self) private var languageStore
    @State private var showDeleteConfirmation = false
    @State private var showDeleteHouseholdConfirmation = false
    @State private var showSignOutConfirmation = false
    @State private var isDeletingAccount = false
    @State private var isDeletingHousehold = false
    @State private var deleteErrorMessage: String?
    @State private var deleteHouseholdTypedName = ""
    @State private var deleteAccountTypedConfirmation = ""
    @State private var isAdvancedExpanded = false

    private var household: Household? {
        appModel.householdStore.activeHousehold
    }

    private var profile: HouseholdProfile? {
        guard let household else { return nil }
        return appModel.householdStore.cachedProfile(for: household.id)
    }

    private var isOwner: Bool {
        household?.role == .owner
    }

    private var canSwitchHouseholds: Bool {
        appModel.householdStore.households.count > 1
    }

    private var householdLoadFailed: Bool {
        appModel.householdStore.activeHousehold == nil
            && !appModel.householdStore.isLoading
            && appModel.householdStore.errorMessage != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VecklyDesign.Spacing.large) {
                if householdLoadFailed {
                    householdErrorView
                } else {
                    householdSummary
                    familyCookbookSection
                    householdSection
                }
                appSection
                accountSection
                advancedSection
            }
            .padding(VecklyDesign.Spacing.large)
        }
        .safeAreaPadding(.bottom, VecklyDesign.Spacing.large)
        .background(VecklyDesign.Colors.canvas)
        .navigationTitle(L10n.string("tabs.household"))
        .task(id: appModel.householdStore.activeHousehold?.id) { await appModel.userProfileStore.load() }
        .task(id: appModel.householdStore.activeHousehold?.id) {
            guard let householdID = appModel.householdStore.activeHousehold?.id else { return }
            await appModel.familyCookbookStore.loadIfNeeded(householdID: householdID)
        }
        .alert(
            deleteHouseholdConfirmationTitle,
            isPresented: $showDeleteHouseholdConfirmation
        ) {
            TextField(household?.name ?? "", text: $deleteHouseholdTypedName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(deleteHouseholdActionTitle, role: .destructive) {
                Task { await deleteHousehold() }
            }
            .disabled(!deleteHouseholdTypedNameMatches)
            Button("common.cancel", role: .cancel) {
                deleteHouseholdTypedName = ""
            }
        } message: {
            Text(deleteHouseholdTypedConfirmationMessage)
        }
        .alert(
            L10n.string("settings.deleteConfirmation"),
            isPresented: $showDeleteConfirmation
        ) {
            TextField(deleteAccountConfirmWord, text: $deleteAccountTypedConfirmation)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("settings.deleteAccount", role: .destructive) {
                Task { await deleteAccount() }
            }
            .disabled(!deleteAccountTypedConfirmationMatches)
            Button("common.cancel", role: .cancel) {
                deleteAccountTypedConfirmation = ""
            }
        } message: {
            Text(deleteAccountTypedConfirmationMessage)
        }
        .confirmationDialog(
            L10n.string("account.signOut.confirmTitle"),
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.string("account.signOut.confirm")) {
                appModel.signOut()
            }
            Button("common.cancel", role: .cancel) {}
        }
        .alert(
            L10n.string("settings.deleteFailed"),
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            ),
            actions: { Button("common.ok") { deleteErrorMessage = nil } },
            message: { Text(deleteErrorMessage ?? "") }
        )
    }

    private var householdErrorView: some View {
        VecklyCard {
            VStack(spacing: VecklyDesign.Spacing.medium) {
                Text(L10n.string("household.loadError"))
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .multilineTextAlignment(.center)
                Button(L10n.string("common.tryAgain")) {
                    Task { await appModel.householdStore.bootstrapAndLoadHouseholds() }
                }
                .buttonStyle(.bordered)
                .tint(VecklyDesign.Colors.hearthOrange)
            }
            .frame(maxWidth: .infinity)
            .padding(VecklyDesign.Spacing.medium)
        }
    }

    private var householdSummary: some View {
        VecklyCard {
            HStack(spacing: VecklyDesign.Spacing.medium) {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .frame(width: 48, height: 48)
                    .background(VecklyDesign.Colors.surfaceStrong)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    if canSwitchHouseholds {
                        householdSwitcher
                    } else {
                        Text(household?.name ?? L10n.string("household.loading"))
                            .font(VecklyDesign.Typography.displayHeading(size: 24))
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    }

                    if let profile {
                        Text(householdSummaryText(profile))
                            .font(.subheadline)
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                    } else if appModel.householdStore.isLoadingDetails || household == nil {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            guard let hid = household?.id else { return }
                            Task { await appModel.householdStore.loadHouseholdDetails(householdID: hid) }
                        } label: {
                            Text(L10n.string("household.detailLoadError"))
                                .font(.subheadline)
                                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("householdDetailRetryButton")
                    }

                    if let household {
                        Text(household.role == .owner ? "household.role.owner" : "household.role.member")
                            .font(.caption)
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // D3 ("Er familj"-panel): framed as a growing family cookbook, never as
    // a dashboard — a headline count, a short favorites list, and a gentle
    // "time again?" nudge, all reading data that already exists (feedback +
    // planning history). Hidden entirely until there's something to show —
    // no empty-state copy for a brand-new household.
    @ViewBuilder
    private var familyCookbookSection: some View {
        if let household, let cookbook = appModel.familyCookbookStore.cookbook(for: household.id), cookbook.totalFamilyLikedCount > 0 {
            VecklyCard {
                VStack(alignment: .leading, spacing: VecklyDesign.Spacing.medium) {
                    Text(L10n.format("household.cookbook.title", cookbook.totalFamilyLikedCount))
                        .font(VecklyDesign.Typography.displayHeading(size: 20))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    ForEach(cookbook.favorites.prefix(5)) { recipe in
                        cookbookRow(title: recipe.title, detail: L10n.format("household.cookbook.timesCooked", recipe.timesCooked))
                    }

                    ForEach(cookbook.dueAgain.prefix(3)) { recipe in
                        cookbookRow(title: recipe.title, detail: L10n.string("household.cookbook.dueAgain"))
                    }
                }
            }
        }
    }

    private func cookbookRow(title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
                .lineLimit(1)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
        }
    }

    private var householdSwitcher: some View {
        Menu {
            ForEach(appModel.householdStore.households) { option in
                Button {
                    Task { await switchHousehold(option) }
                } label: {
                    let displayName = householdDisplayName(for: option)
                    if option.id == household?.id {
                        Label(displayName, systemImage: "checkmark")
                    } else {
                        Text(displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(household?.name ?? L10n.string("household.loading"))
                    .font(VecklyDesign.Typography.displayHeading(size: 24))
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            }
        }
    }

    private func householdDisplayName(for option: Household) -> String {
        let nameCount = appModel.householdStore.households.filter { $0.name == option.name }.count
        guard nameCount > 1 else { return option.name }
        let role = option.role == .owner ? L10n.string("members.owner") : L10n.string("members.member")
        return "\(option.name) (\(role))"
    }

    private var householdSection: some View {
        settingsSection(title: L10n.string("household.section")) {
            NavigationLink {
                HouseholdMembersView()
            } label: {
                navigationRow(
                    title: L10n.string("settings.membersInvites"),
                    systemImage: "person.2",
                    value: appModel.householdStore.members.isEmpty ? nil : String(appModel.householdStore.members.count)
                )
            }
            .accessibilityIdentifier("householdMembersLink")

            Divider()

            NavigationLink {
                HouseholdProfileView()
            } label: {
                navigationRow(title: L10n.string("household.planningFood"), systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("householdPreferencesLink")

            Divider()

            NavigationLink {
                RecipesTabView()
            } label: {
                navigationRow(title: L10n.string("household.familyRecipesLink"), systemImage: "fork.knife")
            }
            .accessibilityIdentifier("familyRecipesLink")

            if isOwner, let household {
                Divider()

                NavigationLink {
                    RenameHouseholdView(householdID: household.id, currentName: household.name)
                } label: {
                    navigationRow(title: L10n.string("household.rename"), systemImage: "pencil")
                }
                .accessibilityIdentifier("renameHouseholdLink")
            }
        }
    }

    private var appSection: some View {
        settingsSection(title: L10n.string("app.section")) {
            NavigationLink {
                LanguageSelectionView()
            } label: {
                navigationRow(
                    title: L10n.string("app.language"),
                    systemImage: "globe",
                    value: languageTitle(languageStore.selection)
                )
            }
            .accessibilityIdentifier("languageSelectionLink")
        }
    }

    private var accountSection: some View {
        settingsSection(title: L10n.string("account.section")) {
            NavigationLink {
                EditDisplayNameView()
            } label: {
                navigationRow(
                    title: L10n.string("settings.displayName"),
                    systemImage: "person.crop.circle",
                    value: appModel.userProfileStore.givenName
                )
            }
            .accessibilityIdentifier("editDisplayNameLink")

            Divider()

            Button {
                showSignOutConfirmation = true
            } label: {
                actionRow(title: L10n.string("settings.signOut"), systemImage: "rectangle.portrait.and.arrow.right", tint: VecklyDesign.Colors.inkMid)
            }
            .accessibilityIdentifier("signOutButton")
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: VecklyDesign.Spacing.small) {
            Text(L10n.string("settings.advanced").uppercased(with: AppLocalePreference.effectiveLocale))
                .font(.caption.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.horizontal, 4)
            VecklyCard {
                DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                    VStack(spacing: 12) {
                        if isOwner {
                            Divider()
                            deleteHouseholdRow
                        }

                        Divider()

                        deleteAccountRow

                        Text("settings.deleteFooter")
                            .font(.footnote)
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    }
                    .padding(.top, VecklyDesign.Spacing.small)
                } label: {
                    // A plain `DisclosureGroup` label outside `List`/`Form`
                    // only reacts to taps on the chevron itself, not the
                    // full row — wrap it in a `Button` so the whole header
                    // toggles, matching `navigationRow`/`actionRow`'s
                    // full-row-tappable convention elsewhere in this view.
                    Button {
                        isAdvancedExpanded.toggle()
                    } label: {
                        Label(L10n.string("settings.advanced"), systemImage: "ellipsis.circle")
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("advancedSectionToggle")
                }
                .tint(VecklyDesign.Colors.inkMid)
            }
        }
    }

    private var deleteHouseholdRow: some View {
        Button(role: .destructive) {
            deleteHouseholdTypedName = ""
            showDeleteHouseholdConfirmation = true
        } label: {
            if isDeletingHousehold {
                HStack {
                    ProgressView()
                    Text(deleteHouseholdInProgressTitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                actionRow(title: deleteHouseholdActionTitle, systemImage: "trash")
            }
        }
        .disabled(isDeletingHousehold)
        .accessibilityIdentifier("deleteHouseholdButton")
    }

    private var deleteAccountRow: some View {
        Button(role: .destructive) {
            deleteAccountTypedConfirmation = ""
            showDeleteConfirmation = true
        } label: {
            if isDeletingAccount {
                HStack {
                    ProgressView()
                    Text("settings.deletingAccount")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                actionRow(title: L10n.string("settings.deleteAccount"), systemImage: "trash")
            }
        }
        .disabled(isDeletingAccount)
        .accessibilityIdentifier("deleteAccountButton")
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: VecklyDesign.Spacing.small) {
            Text(title.uppercased(with: AppLocalePreference.effectiveLocale))
                .font(.caption.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.horizontal, 4)
            VecklyCard {
                VStack(spacing: 12) {
                    content()
                }
            }
        }
    }

    private func navigationRow(title: String, systemImage: String, value: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }

    // `tint` is only applied when explicitly provided (e.g. the neutral
    // sign-out row) — leaving it nil lets the button's own `role`
    // (`.destructive` for the delete rows) drive the label color instead.
    private func actionRow(title: String, systemImage: String, tint: Color? = nil) -> some View {
        Group {
            if let tint {
                Label(title, systemImage: systemImage).foregroundStyle(tint)
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func householdSummaryText(_ profile: HouseholdProfile) -> String {
        let adultsKey = profile.adults == 1 ? "household.summary.adult.one" : "household.summary.adult.other"
        let childrenKey = profile.children == 1 ? "household.summary.child.one" : "household.summary.child.other"
        return L10n.format("household.summary.combined", L10n.format(adultsKey, profile.adults), L10n.format(childrenKey, profile.children))
    }

    private func languageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .system: L10n.string("language.system")
        case .swedish: "Svenska"
        case .english: "English"
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await appModel.deleteAccount()
        } catch {
            deleteErrorMessage = L10n.string("error.settings.deleteAccount")
        }
    }

    private func switchHousehold(_ household: Household) async {
        appModel.householdStore.setActiveHousehold(household)
        await appModel.loadActiveHouseholdReaderData()
    }

    private func deleteHousehold() async {
        guard let household else { return }
        isDeletingHousehold = true
        defer { isDeletingHousehold = false }
        do {
            try await appModel.householdStore.deleteHousehold(householdID: household.id)
            await appModel.loadActiveHouseholdReaderData()
        } catch {
            deleteErrorMessage = deleteHouseholdErrorText
        }
    }

    private var deleteHouseholdActionTitle: String {
        L10n.string("household.delete.action")
    }

    private var deleteHouseholdInProgressTitle: String {
        L10n.string("household.delete.inProgress")
    }

    private var deleteHouseholdConfirmationTitle: String {
        L10n.string("household.delete.confirmTitle")
    }

    private var deleteHouseholdMessage: String {
        L10n.string("household.delete.message")
    }

    private var deleteHouseholdErrorText: String {
        L10n.string("error.household.delete")
    }

    private var deleteHouseholdTypedNameMatches: Bool {
        guard let household else { return false }
        return deleteHouseholdTypedName == household.name
    }

    private var deleteHouseholdTypedConfirmationMessage: String {
        guard let household else { return deleteHouseholdMessage }
        return deleteHouseholdMessage + "\n\n" + L10n.format("household.delete.typeToConfirm", household.name)
    }

    private var deleteAccountConfirmWord: String {
        L10n.string("settings.deleteConfirmWord")
    }

    private var deleteAccountTypedConfirmationMatches: Bool {
        deleteAccountTypedConfirmation == deleteAccountConfirmWord
    }

    private var deleteAccountTypedConfirmationMessage: String {
        L10n.string("settings.deleteMessage") + "\n\n" + L10n.format("settings.deleteTypeToConfirm", deleteAccountConfirmWord)
    }
}
