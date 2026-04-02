import SwiftUI

struct AlbumArtView: View {
    @ObservedObject var release: Release
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                            .font(.system(size: size * 0.3))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 60 ? 8 : 4))
        .accessibilityLabel("Album artwork for \(release.title ?? "unknown") by \(release.displayArtist)")
        .task(id: release.discogsId) {
            let discogsId = release.discogsId
            let localPath = release.localImagePath
            let imageURL = release.imageURL
            image = await ImageCacheService.shared.image(
                discogsId: discogsId,
                localImagePath: localPath,
                imageURL: imageURL
            )
        }
    }
}
