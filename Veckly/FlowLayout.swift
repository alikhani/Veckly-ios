import SwiftUI

/// Left-to-right wrapping layout. Views are placed at their intrinsic size with
/// `spacing` between them horizontally; when a view won't fit on the current
/// row it starts a new one, also separated by `spacing` vertically.
/// Requires iOS 16+ (Layout protocol); the app targets iOS 17, so this is safe.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let containerWidth = proposal.replacingUnspecifiedDimensions().width
        var rowX: CGFloat = 0
        var totalY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let neededX = rowX == 0 ? size.width : rowX + spacing + size.width

            if rowX > 0 && neededX > containerWidth {
                totalY += rowHeight + spacing
                rowX = 0
                rowHeight = 0
            }

            rowX = rowX == 0 ? size.width : rowX + spacing + size.width
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: containerWidth, height: totalY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needsWrap = x > bounds.minX && x + spacing + size.width > bounds.maxX

            if needsWrap {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            } else if x > bounds.minX {
                x += spacing
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}
