import SwiftUI

struct ArtworkTab: View {
    @ObservedObject var release: Release
    @State private var images: [(index: Int, type: String, image: NSImage?)] = []
    @State private var isLoading = false
    @State private var selectedLightboxImage: LightboxItem?
    @State private var isDownloading = false
    @State private var isEnriching = false
    @State private var downloadCurrent = 0
    @State private var downloadTotal = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if images.isEmpty && !isLoading {
                if release.enriched {
                    if release.additionalImages == nil {
                        // Enriched but additionalImages not yet populated (needs re-enrich)
                        ContentUnavailableView {
                            Label("Artwork Not Scanned", systemImage: "photo.on.rectangle")
                        } description: {
                            Text("Re-enrich this release to discover additional artwork.")
                        } actions: {
                            Button {
                                reEnrich()
                            } label: {
                                if isEnriching {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Scan for Artwork")
                                }
                            }
                            .disabled(isEnriching)
                        }
                    } else if release.decodedAdditionalImages?.isEmpty != false {
                        ContentUnavailableView(
                            "No Additional Artwork",
                            systemImage: "photo.on.rectangle",
                            description: Text("This release has no additional images on Discogs.")
                        )
                    } else {
                        // Have URLs but no cached images yet
                        VStack(spacing: 12) {
                            if isDownloading {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.teal)

                                    Text("Downloading artwork...")
                                        .font(.callout)

                                    ProgressView(value: downloadTotal > 0 ? Double(downloadCurrent) / Double(downloadTotal) : 0)
                                        .tint(.teal)
                                        .frame(width: 200)

                                    Text("\(downloadCurrent) of \(downloadTotal)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                ContentUnavailableView {
                                    Label("Artwork Not Downloaded", systemImage: "arrow.down.circle")
                                } description: {
                                    Text("\(release.decodedAdditionalImages?.count ?? 0) images available.")
                                } actions: {
                                    Button("Download Artwork") {
                                        downloadImages()
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Not Enriched", systemImage: "photo.on.rectangle")
                    } description: {
                        Text("Enrich this release first to discover additional artwork.")
                    }
                }
            } else {
                // Image grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 300))], spacing: 16) {
                    // Primary image
                    primaryImageCard

                    // Additional images
                    ForEach(images, id: \.index) { item in
                        imageCard(item: item)
                    }
                }
            }

            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading artwork...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: release.discogsId) {
            await loadImages()
        }
        .sheet(item: $selectedLightboxImage) { item in
            LightboxView(image: item.image)
        }
    }

    // MARK: - Primary Image Card

    private var primaryImageCard: some View {
        VStack(spacing: 4) {
            AlbumArtView(release: release, size: 250)
                .onTapGesture {
                    Task {
                        if let img = await ImageCacheService.shared.image(
                            discogsId: release.discogsId,
                            localImagePath: release.localImagePath,
                            imageURL: release.imageURL
                        ) {
                            selectedLightboxImage = LightboxItem(id: -1, image: img)
                        }
                    }
                }

            Text("Primary")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Additional Image Card

    private func imageCard(item: (index: Int, type: String, image: NSImage?)) -> some View {
        VStack(spacing: 4) {
            Group {
                if let image = item.image {
                    Button {
                        selectedLightboxImage = LightboxItem(id: item.index, image: image)
                    } label: {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.type) artwork")
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                                .font(.title)
                        }
                }
            }
            .frame(width: 250, height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(item.type.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Load & Download

    private func loadImages() async {
        guard let additionalImages = release.decodedAdditionalImages, !additionalImages.isEmpty else {
            images = []
            return
        }

        isLoading = true
        let discogsId = release.discogsId
        var loaded: [(index: Int, type: String, image: NSImage?)] = []

        for (index, info) in additionalImages.enumerated() {
            let img = await ImageCacheService.shared.additionalImage(discogsId: discogsId, imageIndex: index)
            if img != nil {
                loaded.append((index: index, type: info.typeLabel, image: img))
            }
        }

        images = loaded
        isLoading = false
    }

    private func reEnrich() {
        isEnriching = true
        let objectID = release.objectID
        Task {
            let syncService = SyncService()
            await syncService.enrichSingleRelease(objectID)
            await loadImages()
            isEnriching = false
        }
    }

    private func redownloadImages() {
        isDownloading = true
        let discogsId = release.discogsId
        let additionalImages = release.decodedAdditionalImages ?? []
        downloadCurrent = 0
        downloadTotal = additionalImages.count

        Task {
            // Delete existing cached files first
            for (index, _) in additionalImages.enumerated() {
                await ImageCacheService.shared.deleteAdditionalImage(discogsId: discogsId, imageIndex: index)
            }

            // Re-download all
            for (index, info) in additionalImages.enumerated() {
                if let url = URL(string: info.uri) {
                    _ = await ImageCacheService.shared.downloadAdditionalImage(discogsId: discogsId, imageIndex: index, url: url)
                }
                downloadCurrent = index + 1
            }
            await loadImages()
            isDownloading = false
        }
    }

    private func downloadImages() {
        isDownloading = true
        let discogsId = release.discogsId
        let additionalImages = release.decodedAdditionalImages ?? []
        downloadCurrent = 0
        downloadTotal = additionalImages.count

        Task {
            for (index, info) in additionalImages.enumerated() {
                if let url = URL(string: info.uri) {
                    _ = await ImageCacheService.shared.downloadAdditionalImage(discogsId: discogsId, imageIndex: index, url: url)
                }
                downloadCurrent = index + 1
            }
            await loadImages()
            isDownloading = false
        }
    }
}

// MARK: - Lightbox

struct LightboxItem: Identifiable {
    let id: Int
    let image: NSImage
}

struct LightboxView: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.95)

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(20)
                .accessibilityLabel("Full size artwork")
        }
        .frame(minWidth: 600, minHeight: 600)
        .onTapGesture {
            dismiss()
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding()
        }
    }
}
