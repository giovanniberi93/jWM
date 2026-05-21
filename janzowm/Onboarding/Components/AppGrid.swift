import SwiftUI

/// 6-column grid of installed apps for slot picking. Apps already bound to
/// the *other* tutorial slot are dimmed and non-interactive so the user
/// can't pick the same app for both slots.
struct AppGrid: View {
    let apps: [InstalledApp]
    let dimmedBundleIDs: Set<String>
    let selectedBundleID: String
    let onPick: (InstalledApp) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(apps) { app in
                    AppCell(
                        app: app,
                        dimmed: dimmedBundleIDs.contains(app.bundleID),
                        selected: selectedBundleID == app.bundleID,
                        onPick: onPick
                    )
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(TutorialTokens.rule, lineWidth: 0.5)
        )
    }
}

private struct AppCell: View {
    let app: InstalledApp
    let dimmed: Bool
    let selected: Bool
    let onPick: (InstalledApp) -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            onPick(app)
        } label: {
            VStack(spacing: 6) {
                Image(nsImage: app.icon())
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                Text(app.name)
                    .font(.system(size: 11))
                    .foregroundStyle(TutorialTokens.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? TutorialTokens.blue.opacity(0.14)
                          : (hovering ? TutorialTokens.blue.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.4 : 1)
        .allowsHitTesting(!dimmed)
        .onHover { hovering = $0 && !dimmed }
    }
}
