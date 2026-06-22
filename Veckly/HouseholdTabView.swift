import SwiftUI

struct HouseholdTabView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppLanguageStore.self) private var languageStore
    @State private var showDeleteConfirmation = false
    @State private var showDeleteHouseholdConfirmation = false
    @State private var isDeletingAccount = false
    @State private var isDeletingHousehold = false
    @State private var deleteErrorMessage: String?

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VecklyDesign.Spacing.large) {
                householdSummary
                householdSection
                appSection
                accountSection
            }
            .padding(VecklyDesign.Spacing.large)
        }
        .background(VecklyDesign.Colors.canvas)
        .navigationTitle(L10n.string("tabs.household"))
        .confirmationDialog(
            deleteHouseholdConfirmationTitle,
            isPresented: $showDeleteHouseholdConfirmation,
            titleVisibility: .visible
        ) {
            Button(deleteHouseholdActionTitle, role: .destructive) {
                Task { await deleteHousehold() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text(deleteHouseholdMessage)
        }
        .confirmationDialog(
            L10n.string("settings.deleteConfirmation"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("settings.deleteAccount", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("settings.deleteMessage")
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

    private var householdSwitcher: some View {
        Menu {
            ForEach(appModel.householdStore.households) { option in
                Button {
                    Task { await switchHousehold(option) }
                } label: {
                    if option.id == household?.id {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
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

            if isOwner, let household {
                Divider()

                NavigationLink {
                    RenameHouseholdView(householdID: household.id, currentName: household.name)
                } label: {
                    navigationRow(title: L10n.string("household.rename"), systemImage: "pencil")
                }
                .accessibilityIdentifier("renameHouseholdLink")

                Divider()

                Button(role: .destructive) {
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
            Button(role: .destructive) {
                appModel.signOut()
            } label: {
                actionRow(title: L10n.string("settings.signOut"), systemImage: "rectangle.portrait.and.arrow.right")
            }
            .accessibilityIdentifier("signOutButton")

            Divider()

            Button(role: .destructive) {
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

            Text("settings.deleteFooter")
                .font(.footnote)
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
        }
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

    private func actionRow(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
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
}
