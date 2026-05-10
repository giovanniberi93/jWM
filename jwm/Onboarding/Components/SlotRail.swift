import SwiftUI

/// Horizontal row of 10 keycap-style slot tiles (1..9, 0). The slot the
/// user is binding now (`targetSlot`) gets a blue ring; the rest render
/// empty. Reuses the same `SlotKeycap` component as the Settings UI so the
/// two surfaces stay pixel-identical.
struct SlotRail: View {
    let targetSlot: Int

    private static let order = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
    @State private var hoveredSlot: Int? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.order, id: \.self) { slot in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        SlotKeycap(
                            slot: slot,
                            shifted: false,
                            hovered: hoveredSlot == slot,
                            target: slot == targetSlot,
                            showClearBadge: slot == targetSlot,
                            forceEmpty: slot != targetSlot,
                            onHoverChange: { isHover, _ in
                                if isHover {
                                    hoveredSlot = slot
                                } else if hoveredSlot == slot {
                                    hoveredSlot = nil
                                }
                            },
                            onTap: {}
                        )
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quinary))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 1)
        )
    }
}
