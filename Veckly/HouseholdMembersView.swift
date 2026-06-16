import SwiftUI
import UIKit

struct HouseholdMembersView: View {
    @Environment(AppModel.self) private var appModel
    @State private var tokenInput = ""
    @State private var landing: InviteLanding?
    @State private var landingToken: String?
    @State private var isLookingUp = false
    @State private var isJoining = false
    @State private var isCreatingInvite = false
    @State private var revokingInviteIDs: Set<String> = []
    @State private var newInvite: HouseholdInvite?
    @State private var errorMessage: String?

    private var household: Household? { appModel.householdStore.activeHousehold }
    private var isOwner: Bool { household?.role == .owner }
    private var myUserID: String { appModel.authSessionStore.userID ?? "" }

    var body: some View {
        Form {
            membersSection
            if isOwner { inviteSection }
            joinSection
        }
        .navigationTitle("Members")
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: { Text(errorMessage ?? "") })
        .sheet(item: $newInvite) { invite in
            InviteShareSheet(invite: invite)
        }
        .task(id: household?.id) {
            guard let hid = household?.id else { return }
            await appModel.householdStore.loadHouseholdDetails(householdID: hid)
            if isOwner { await appModel.householdStore.loadInvites(householdID: hid) }
        }
        .onChange(of: tokenInput) { _, _ in
            landing = nil
            landingToken = nil
        }
    }

    private var membersSection: some View {
        Section("Members") {
            if appModel.householdStore.isLoadingDetails {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let message = appModel.householdStore.detailsErrorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    Button("Try again") {
                        guard let hid = household?.id else { return }
                        Task { await appModel.householdStore.loadHouseholdDetails(householdID: hid) }
                    }
                }
            } else if appModel.householdStore.members.isEmpty {
                Text("No members yet")
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            } else {
                ForEach(appModel.householdStore.members) { member in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if member.userId == myUserID {
                                Text("You")
                                    .font(.body.weight(.medium))
                            } else {
                                Text(member.userId.prefix(8) + "…")
                                    .font(.body.monospaced())
                                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                            }
                        }
                        Spacer()
                        Text(member.role == .owner ? "Owner" : "Member")
                            .font(.caption)
                            .foregroundStyle(member.role == .owner ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkFaint)
                    }
                }
            }
        }
    }

    private var inviteSection: some View {
        Section {
            Button {
                Task { await createInvite() }
            } label: {
                if isCreatingInvite {
                    HStack { ProgressView(); Text("Creating…") }
                } else {
                    Label("Create invite link", systemImage: "link.badge.plus")
                        .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                }
            }
            .disabled(isCreatingInvite)

            if appModel.householdStore.isLoadingInvites {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let message = appModel.householdStore.invitesErrorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    Button("Try again") {
                        guard let hid = household?.id else { return }
                        Task { await appModel.householdStore.loadInvites(householdID: hid) }
                    }
                }
            } else if appModel.householdStore.invites.filter({ $0.status == "pending" }).isEmpty {
                Text("No open invites")
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }

            ForEach(appModel.householdStore.invites.filter { $0.status == "pending" }) { invite in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invite.token.prefix(8) + "…")
                            .font(.caption.monospaced())
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        Text("Pending")
                            .font(.caption2)
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await revokeInvite(invite) }
                    } label: {
                        if revokingInviteIDs.contains(invite.id) {
                            ProgressView()
                        } else {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(revokingInviteIDs.contains(invite.id))
                }
            }
        } header: {
            Text("Invite someone")
        }
    }

    private var joinSection: some View {
        Section {
            TextField("Paste invite token", text: $tokenInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if let landing {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(landing.householdName)
                            .font(.body.weight(.medium))
                        Text(landing.status == "pending" ? "Open invite" : landing.status.capitalized)
                            .font(.caption)
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    }
                    Spacer()
                    if landing.status == "pending" {
                        Button("Join") {
                            Task { await joinHousehold() }
                        }
                        .disabled(isJoining || landingToken == nil)
                        .buttonStyle(.borderedProminent)
                        .tint(VecklyDesign.Colors.hearthOrange)
                        .controlSize(.small)
                    }
                }
            }

            Button {
                Task { await lookUpToken() }
            } label: {
                if isLookingUp {
                    HStack { ProgressView(); Text("Looking up…") }
                } else {
                    Text("Look up token")
                }
            }
            .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLookingUp)
        } header: {
            Text("Join a household")
        } footer: {
            Text("Ask a household owner to share their invite token with you.")
        }
    }

    private func createInvite() async {
        guard let hid = household?.id else { return }
        isCreatingInvite = true
        defer { isCreatingInvite = false }
        do {
            newInvite = try await appModel.householdStore.createInvite(householdID: hid)
        } catch {
            errorMessage = "Could not create invite. Try again."
        }
    }

    private func revokeInvite(_ invite: HouseholdInvite) async {
        guard let hid = household?.id else { return }
        revokingInviteIDs.insert(invite.id)
        defer { revokingInviteIDs.remove(invite.id) }
        do {
            try await appModel.householdStore.revokeInvite(householdID: hid, inviteID: invite.id)
        } catch {
            errorMessage = "Could not revoke invite."
        }
    }

    private func lookUpToken() async {
        isLookingUp = true
        landing = nil
        landingToken = nil
        defer { isLookingUp = false }
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            landing = try await appModel.householdStore.lookupInvite(token: token)
            landingToken = token
        } catch APIError.notFound {
            errorMessage = "No invite found for that token."
        } catch {
            errorMessage = "Could not look up the token."
        }
    }

    private func joinHousehold() async {
        guard let token = landingToken else { return }
        isJoining = true
        defer { isJoining = false }
        do {
            _ = try await appModel.householdStore.acceptInvite(token: token)
            landing = nil
            landingToken = nil
            tokenInput = ""
            await appModel.loadActiveHouseholdReaderData()
        } catch APIError.server(409) {
            errorMessage = "This invite is no longer valid (revoked or expired)."
        } catch {
            errorMessage = "Could not join the household."
        }
    }
}

private struct InviteShareSheet: View {
    let invite: HouseholdInvite
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)

                VStack(spacing: 8) {
                    Text("Invite created")
                        .font(.title2.weight(.semibold))
                    Text("Share this token with the person you want to invite. They paste it in the \"Join a household\" section.")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .multilineTextAlignment(.center)
                }

                Text(invite.token)
                    .font(.body.monospaced())
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    UIPasteboard.general.string = invite.token
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied" : "Copy token", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(VecklyDesign.Colors.inkMid)
                .controlSize(.large)

                ShareLink(item: invite.token) {
                    Label("Share token", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(VecklyDesign.Colors.hearthOrange)
                .controlSize(.large)

                Spacer()
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
