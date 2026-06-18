import SwiftUI

struct ReleaseRow: View {
    @ObservedObject var release: Release

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtView(release: release, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(release.title ?? "Untitled")
                    .font(.body)
                    .lineLimit(1)

                Text(release.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(release.displayYear)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(release.format ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if release.rating > 0 {
                Text(release.displayRating)
                    .font(.caption2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [release.title ?? "Untitled", "by \(release.displayArtist)"]
        if release.year > 0 { parts.append(release.displayYear) }
        if let format = release.format, !format.isEmpty { parts.append(format) }
        if release.rating > 0 { parts.append(release.accessibilityRating) }
        return parts.joined(separator: ", ")
    }
}
