import SwiftUI

struct ShoppingHandoffStatusCard: View {
    let state: ShoppingListHandoffState

    var body: some View {
        VecklyCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch state {
        case .ready: "cart"
        case .completed: "checkmark.seal"
        }
    }

    private var title: String {
        switch state {
        case .ready: L10n.string("shopping.handoff.ready.title")
        case .completed: L10n.string("shopping.handoff.completed.title")
        }
    }

    private var message: String {
        switch state {
        case .ready(let totalItems, let checkedItems):
            L10n.format("shopping.handoff.ready.message", checkedItems, totalItems)
        case .completed:
            L10n.string("shopping.handoff.completed.message")
        }
    }
}
