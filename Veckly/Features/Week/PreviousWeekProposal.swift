import SwiftUI

struct PreviousWeekProposalDay: Equatable, Identifiable {
    enum Action: Equatable { case kept, replaced, added }

    let dayOfWeek: String
    let date: String
    let action: Action
    let reason: String
    let previousRecipeTitle: String?
    let recipeTitle: String
    let servings: Int
    var id: String { date }

    var reasonText: String {
        switch reason {
        case "worked-last-week": L10n.string("previousWeek.reason.worked-last-week")
        case "not-cooked": L10n.string("previousWeek.reason.not-cooked")
        case "family-veto": L10n.string("previousWeek.reason.family-veto")
        case "disliked": L10n.string("previousWeek.reason.disliked")
        case "fatigued": L10n.string("previousWeek.reason.fatigued")
        case "changed-plan-often": L10n.string("previousWeek.reason.changed-plan-often")
        case "week-context": L10n.string("previousWeek.reason.week-context")
        default: L10n.string("previousWeek.reason.fills-selected-day")
        }
    }
}

struct PreviousWeekProposal: Equatable {
    let proposalID: String
    let sourceWeekStartDate: String
    let expectedUpdatedAt: String?
    let keptCount: Int
    let changedCount: Int
    let days: [PreviousWeekProposalDay]
}

private extension Components.Schemas.PreviousWeekProposalDay {
    var appModel: PreviousWeekProposalDay {
        PreviousWeekProposalDay(
            dayOfWeek: dayOfWeek.rawValue,
            date: date,
            action: action == .kept ? .kept : action == .replaced ? .replaced : .added,
            reason: reason.rawValue,
            previousRecipeTitle: previousRecipeTitle,
            recipeTitle: recipeTitle,
            servings: servings
        )
    }
}

private extension Components.Schemas.PreviousWeekProposal {
    var appModel: PreviousWeekProposal {
        PreviousWeekProposal(
            proposalID: proposalId,
            sourceWeekStartDate: sourceWeekStartDate,
            expectedUpdatedAt: expectedUpdatedAt,
            keptCount: keptCount,
            changedCount: changedCount,
            days: days.map(\.appModel)
        )
    }
}

extension VecklyAPIClient {
    func previewPreviousWeekProposal(
        householdID: String, weekStartDate: String, proposalID: String, expectedUpdatedAt: String?
    ) async throws -> PreviousWeekProposal {
        let output = try await _client.previewPreviousWeekProposal(
            path: .init(householdId: householdID, weekStartDate: weekStartDate),
            body: .json(.init(proposalId: proposalID, expectedUpdatedAt: expectedUpdatedAt))
        )
        switch output {
        case let .ok(response): return try response.body.json.appModel
        case .unauthorized: throw APIError.unauthorized
        case .notFound: throw APIError.notFound
        case .conflict: throw APIError.server(statusCode: 409)
        case .unprocessableContent: throw APIError.server(statusCode: 422)
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func applyPreviousWeekProposal(
        householdID: String, weekStartDate: String, proposalID: String, expectedUpdatedAt: String?
    ) async throws {
        let output = try await _client.applyPreviousWeekProposal(
            path: .init(householdId: householdID, weekStartDate: weekStartDate),
            body: .json(.init(proposalId: proposalID, expectedUpdatedAt: expectedUpdatedAt))
        )
        switch output {
        case .ok: return
        case .unauthorized: throw APIError.unauthorized
        case .notFound: throw APIError.notFound
        case .conflict: throw APIError.server(statusCode: 409)
        case .unprocessableContent: throw APIError.server(statusCode: 422)
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }
}

struct PreviousWeekProposalSheet: View {
    let household: Household
    let weekStartDate: String
    let expectedUpdatedAt: String?
    let onApplied: () async -> Void
    let onSwap: (String) -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var proposalID = UUID().uuidString.lowercased()
    @State private var proposal: PreviousWeekProposal?
    @State private var isLoading = true
    @State private var isApplying = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let proposal {
                    List {
                        Section {
                            Text(L10n.format("previousWeek.summary", proposal.keptCount, proposal.changedCount))
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                            if let errorMessage {
                                Text(errorMessage)
                                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                            }
                        }
                        Section("previousWeek.plan") {
                            ForEach(proposal.days) { day in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(WeekCalendar.shortDateLabel(yyyyMmDd: day.date))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                                            Text(day.recipeTitle).font(.body.weight(.semibold))
                                            Text(day.reasonText).font(.footnote).foregroundStyle(VecklyDesign.Colors.inkMid)
                                        }
                                        Spacer()
                                        if day.action == .kept {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                                                .accessibilityLabel(L10n.string("previousWeek.kept"))
                                        } else {
                                            Button("previousWeek.swap") { Task { await apply(proposal, thenChange: day.date) } }
                                                .font(.footnote.weight(.semibold))
                                                .disabled(isApplying)
                                                .accessibilityHint(Text("previousWeek.swap.hint"))
                                        }
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                } else if isLoading {
                    ProgressView("previousWeek.loading")
                } else {
                    ContentUnavailableView("previousWeek.unavailable", systemImage: "calendar.badge.exclamationmark", description: Text(errorMessage ?? ""))
                }
            }
            .navigationTitle("previousWeek.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.close") { dismiss() } }
                if let proposal {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("previousWeek.usePlan") { Task { await apply(proposal) } }
                            .disabled(isApplying)
                    }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            proposal = try await appModel.weekStore.previewPreviousWeek(
                household: household, weekStartDate: weekStartDate,
                proposalID: proposalID, expectedUpdatedAt: expectedUpdatedAt
            )
        } catch where WeekStore.isStaleWeekPlan(error) {
            errorMessage = L10n.string("error.week.stale")
        } catch {
            errorMessage = L10n.string("previousWeek.error.preview")
        }
    }

    /// `thenChange` is the per-day "Change" path: the proposal is generated
    /// and applied server-side as a whole (by `proposalId`), so the client
    /// can't apply it minus one day. Changing a day therefore uses the plan
    /// first — same path, same stale-plan recovery as "Use this week" — and
    /// then opens the meal picker for that day on the now-filled week.
    private func apply(_ proposal: PreviousWeekProposal, thenChange date: String? = nil) async {
        isApplying = true
        defer { isApplying = false }
        do {
            try await Self.commit(
                proposal, thenChange: date,
                weekStore: appModel.weekStore, household: household, weekStartDate: weekStartDate,
                onApplied: onApplied, onChangeDay: onSwap
            )
            dismiss()
        } catch where WeekStore.isStaleWeekPlan(error) {
            self.proposal = nil
            errorMessage = nil
            await load()
            if errorMessage == nil { errorMessage = L10n.string("error.week.changedSincePreview") }
        } catch {
            errorMessage = L10n.string("previousWeek.error.apply")
        }
    }

    static func commit(
        _ proposal: PreviousWeekProposal,
        thenChange date: String?,
        weekStore: WeekStore,
        household: Household,
        weekStartDate: String,
        onApplied: () async -> Void,
        onChangeDay: (String) -> Void
    ) async throws {
        try await weekStore.applyPreviousWeek(household: household, weekStartDate: weekStartDate, proposal: proposal)
        await onApplied()
        if let date { onChangeDay(date) }
    }
}
