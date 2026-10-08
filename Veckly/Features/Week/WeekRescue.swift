import SwiftUI

enum WeekRescueIntent: String, CaseIterable, Identifiable {
    case quick
    case noEnergy
    case missingIngredient
    case extraGuest
    case swapDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: L10n.string("rescue.intent.quick")
        case .noEnergy: L10n.string("rescue.intent.noEnergy")
        case .missingIngredient: L10n.string("rescue.intent.missingIngredient")
        case .extraGuest: L10n.string("rescue.intent.extraGuest")
        case .swapDay: L10n.string("rescue.intent.swapDay")
        }
    }

    var apiValue: Components.Schemas.WeekRescueIntent {
        switch self {
        case .quick: .quick
        case .noEnergy: .no_hyphen_energy
        case .missingIngredient: .missing_hyphen_ingredient
        case .extraGuest: .extra_hyphen_guest
        case .swapDay: .swap_hyphen_day
        }
    }
}

struct WeekRescueChange: Equatable {
    let date: String
    let beforeTitle: String?
    let afterTitle: String?
    let beforeServings: Int?
    let afterServings: Int?
}

struct WeekRescuePreview: Equatable {
    let rescueID: String
    let intent: WeekRescueIntent
    let primaryChange: WeekRescueChange
    let followUpChanges: [WeekRescueChange]
    let addedShoppingItems: [String]
    let removedShoppingItems: [String]
    let expectedUpdatedAt: String?

    var changeSummary: String {
        if primaryChange.beforeTitle == primaryChange.afterTitle,
           let servings = primaryChange.afterServings {
            return L10n.format("rescue.preview.servings", primaryChange.afterTitle ?? "", servings)
        }
        return L10n.format("rescue.preview.swap", primaryChange.beforeTitle ?? "", primaryChange.afterTitle ?? "")
    }
}

private extension Components.Schemas.WeekRescueChange {
    var appModel: WeekRescueChange {
        WeekRescueChange(
            date: date,
            beforeTitle: beforeRecipeTitle,
            afterTitle: afterRecipeTitle,
            beforeServings: beforeServings,
            afterServings: afterServings
        )
    }
}

private extension Components.Schemas.WeekRescuePreview {
    func appModel(intent: WeekRescueIntent) -> WeekRescuePreview {
        WeekRescuePreview(
            rescueID: rescueId,
            intent: intent,
            primaryChange: primaryChange.appModel,
            followUpChanges: followUpChanges.map(\.appModel),
            addedShoppingItems: shoppingDiff.added,
            removedShoppingItems: shoppingDiff.removed,
            expectedUpdatedAt: expectedUpdatedAt
        )
    }
}

extension VecklyAPIClient {
    func previewWeekRescue(
        householdID: String,
        weekStartDate: String,
        date: String,
        intent: WeekRescueIntent,
        missingIngredient: String?,
        rescueID: String,
        expectedUpdatedAt: String?
    ) async throws -> WeekRescuePreview {
        let request = Components.Schemas.WeekRescueRequest(
            rescueId: rescueID,
            date: date,
            intent: intent.apiValue,
            missingIngredient: missingIngredient,
            expectedUpdatedAt: expectedUpdatedAt
        )
        let output = try await _client.previewWeekRescue(
            path: .init(householdId: householdID, weekStartDate: weekStartDate),
            body: .json(request)
        )
        switch output {
        case let .ok(response): return try response.body.json.appModel(intent: intent)
        case .badRequest: throw APIError.server(statusCode: 400)
        case .unauthorized: throw APIError.unauthorized
        case .notFound: throw APIError.notFound
        case .conflict: throw APIError.server(statusCode: 409)
        case .unprocessableContent: throw APIError.server(statusCode: 422)
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func applyWeekRescue(
        householdID: String,
        weekStartDate: String,
        date: String,
        intent: WeekRescueIntent,
        missingIngredient: String?,
        rescueID: String,
        expectedUpdatedAt: String?
    ) async throws {
        let request = Components.Schemas.WeekRescueRequest(
            rescueId: rescueID,
            date: date,
            intent: intent.apiValue,
            missingIngredient: missingIngredient,
            expectedUpdatedAt: expectedUpdatedAt
        )
        let output = try await _client.applyWeekRescue(
            path: .init(householdId: householdID, weekStartDate: weekStartDate),
            body: .json(request)
        )
        switch output {
        case .ok: return
        case .badRequest: throw APIError.server(statusCode: 400)
        case .unauthorized: throw APIError.unauthorized
        case .notFound: throw APIError.notFound
        case .conflict: throw APIError.server(statusCode: 409)
        case .unprocessableContent: throw APIError.server(statusCode: 422)
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }
}

struct WeekRescueSheet: View {
    let day: WeekDayRowViewModel
    let household: Household
    let weekStartDate: String
    let expectedUpdatedAt: String?
    let onApplied: () async -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIntent: WeekRescueIntent?
    @State private var missingIngredient = ""
    @State private var rescueID = UUID().uuidString.lowercased()
    @State private var preview: WeekRescuePreview?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let preview {
                    previewSection(preview)
                } else {
                    Section("rescue.question") {
                        ForEach(WeekRescueIntent.allCases) { intent in
                            Button(intent.title) {
                                selectedIntent = intent
                                if intent != .missingIngredient { Task { await loadPreview() } }
                            }
                        }
                    }
                    if selectedIntent == .missingIngredient {
                        Section("rescue.missing.label") {
                            TextField("rescue.missing.placeholder", text: $missingIngredient)
                            Button("rescue.findSuggestion") { Task { await loadPreview() } }
                                .disabled(missingIngredient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .overlay { if isLoading { ProgressView() } }
            .navigationTitle("rescue.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func previewSection(_ preview: WeekRescuePreview) -> some View {
        Section("rescue.preview.title") {
            Text(preview.changeSummary).font(.headline)
            ForEach(Array(preview.followUpChanges.enumerated()), id: \.offset) { _, change in
                Text(L10n.format("rescue.preview.followUp", WeekCalendar.shortDateLabel(yyyyMmDd: change.date), change.afterTitle ?? ""))
            }
        }
        Section("rescue.preview.shopping") {
            if preview.addedShoppingItems.isEmpty && preview.removedShoppingItems.isEmpty {
                Text("rescue.preview.shoppingUnchanged")
            } else {
                ForEach(preview.addedShoppingItems, id: \.self) { Text(L10n.format("rescue.preview.add", $0)) }
                ForEach(preview.removedShoppingItems, id: \.self) { Text(L10n.format("rescue.preview.remove", $0)) }
            }
        }
        Section {
            Button("rescue.confirm") { Task { await apply(preview) } }
                .buttonStyle(.borderedProminent)
                .tint(VecklyDesign.Colors.hearthOrangePrimaryFill)
                .frame(maxWidth: .infinity)
        }
    }

    private func loadPreview() async {
        guard let selectedIntent else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            preview = try await appModel.weekStore.previewRescue(
                day: day, household: household, weekStartDate: weekStartDate,
                intent: selectedIntent, missingIngredient: missingIngredient,
                rescueID: rescueID, expectedUpdatedAt: expectedUpdatedAt
            )
        } catch where WeekStore.isStaleWeekPlan(error) {
            errorMessage = L10n.string("error.week.stale")
        } catch {
            errorMessage = L10n.string("rescue.error.noSuggestion")
        }
    }

    private func apply(_ preview: WeekRescuePreview) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await appModel.weekStore.applyRescue(
                day: day, household: household, weekStartDate: weekStartDate,
                preview: preview, missingIngredient: missingIngredient
            )
            await onApplied()
            dismiss()
        } catch where WeekStore.isStaleWeekPlan(error) {
            // The plan changed after this preview was shown — never apply a
            // stale suggestion; show a fresh one to confirm instead.
            self.preview = nil
            await loadPreview()
            if errorMessage == nil { errorMessage = L10n.string("error.week.changedSincePreview") }
        } catch {
            errorMessage = L10n.string("rescue.error.apply")
        }
    }
}
