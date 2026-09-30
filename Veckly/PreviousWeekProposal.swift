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
                                            Button("previousWeek.swap") { onSwap(day.date); dismiss() }
                                                .font(.footnote.weight(.semibold))
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
        } catch {
            errorMessage = L10n.string("previousWeek.error.preview")
        }
    }

    private func apply(_ proposal: PreviousWeekProposal) async {
        isApplying = true
        defer { isApplying = false }
        do {
            try await appModel.weekStore.applyPreviousWeek(household: household, weekStartDate: weekStartDate, proposal: proposal)
            await onApplied()
            dismiss()
        } catch {
            errorMessage = L10n.string("previousWeek.error.apply")
        }
    }
}
