import SwiftUI

struct ReleaseCard: View {
    @ObservedObject var release: Release

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AlbumArtView(release: release, size: 180)

            VStack(alignment: .leading, spacing: 2) {
                Text(release.title ?? "Untitled")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Text(release.artist ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack {
                    Text(release.displayYear)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let format = release.format, !format.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(format)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}
