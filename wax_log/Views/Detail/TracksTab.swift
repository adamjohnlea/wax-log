import SwiftUI
import MusicKit

struct TracksTab: View {
    @ObservedObject var release: Release
    @State private var isEnriching = false
    @State private var appleMusicAlbum: Album?
    @State private var appleMusicTracks: [Track]?
    @State private var isLoadingAppleMusic = false
    @State private var appleMusicError: String?
    @State private var musicAuthStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @State private var playingTrackIndex: Int?
    @State private var isPlaying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Discogs tracklist
            if let tracks = release.decodedTracklist, !tracks.isEmpty {
                GroupBox("Tracklist") {
                    VStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                            HStack {
                                Text(track.position.isEmpty ? "\(index + 1)" : track.position)
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, alignment: .trailing)

                                Text(track.title)
                                    .font(.callout)

                                Spacer()

                                if !track.duration.isEmpty {
                                    Text(track.duration)
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)

                            if index < tracks.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if !release.enriched {
                ContentUnavailableView {
                    Label("No Tracklist", systemImage: "music.note.list")
                } description: {
                    Text("Enrich this release to load the tracklist from Discogs.")
                } actions: {
                    Button {
                        enrich()
                    } label: {
                        if isEnriching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Enrich Now")
                        }
                    }
                    .disabled(isEnriching)
                }
            } else {
                ContentUnavailableView(
                    "No Tracklist Available",
                    systemImage: "music.note.list",
                    description: Text("This release has no tracklist data on Discogs.")
                )
            }

            // Apple Music section
            appleMusicSection
        }
        .task(id: release.discogsId) {
            appleMusicAlbum = nil
            appleMusicTracks = nil
            appleMusicError = nil
            musicAuthStatus = MusicAuthorization.currentStatus
            if musicAuthStatus == .authorized {
                await loadAppleMusicMatch()
            }
        }
    }

    // MARK: - Apple Music Section

    @ViewBuilder
    private var appleMusicSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "apple.logo")
                    Text("Apple Music")
                        .font(.headline)
                    Spacer()
                }

                switch musicAuthStatus {
                case .notDetermined:
                    Button("Connect Apple Music") {
                        Task {
                            let authorized = await AppleMusicService.shared.requestAuthorization()
                            musicAuthStatus = MusicAuthorization.currentStatus
                            if authorized {
                                await loadAppleMusicMatch()
                            }
                        }
                    }

                case .authorized:
                    if isLoadingAppleMusic {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching Apple Music...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else if let album = appleMusicAlbum {
                        appleMusicAlbumView(album)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                Text("No match found on Apple Music")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button("Retry") {
                                    appleMusicError = nil
                                    Task { await loadAppleMusicMatch() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            if let error = appleMusicError {
                                Text("Error: \(error)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }

                            Text("Searched: \(release.artist ?? "?") — \(release.title ?? "?")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                case .denied, .restricted:
                    Text("Apple Music access is not available. Enable it in System Settings > Privacy.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func appleMusicAlbumView(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let artwork = album.artwork {
                    ArtworkImage(artwork, width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.callout.weight(.medium))
                    Text(album.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let releaseDate = album.releaseDate {
                        Text(releaseDate, format: .dateTime.year())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button {
                    openInAppleMusic(album)
                } label: {
                    Label("Open", systemImage: "arrow.up.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Apple Music tracks with play buttons
            if let tracks = appleMusicTracks, !tracks.isEmpty {
                Divider()

                // Playback controls
                if isPlaying || playingTrackIndex != nil {
                    HStack {
                        Button {
                            togglePlayPause()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.borderless)

                        if let index = playingTrackIndex, index < tracks.count {
                            Text("Now playing: \(tracks[index].title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            stopPlayback()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }

                VStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        HStack {
                            Button {
                                playTrack(track, at: index)
                            } label: {
                                Image(systemName: playingTrackIndex == index && isPlaying ? "speaker.wave.2.fill" : "play.circle")
                                    .font(.title3)
                                    .foregroundStyle(playingTrackIndex == index ? .pink : .secondary)
                            }
                            .buttonStyle(.plain)

                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)

                            Text(track.title)
                                .font(.callout)
                                .fontWeight(playingTrackIndex == index ? .medium : .regular)
                                .lineLimit(1)

                            Spacer()

                            if let duration = track.duration {
                                Text(formatDuration(duration))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        if index < tracks.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadAppleMusicMatch() async {
        isLoadingAppleMusic = true
        appleMusicError = nil
        let artist = release.artist
        let title = release.title
        let discogsId = release.discogsId

        do {
            appleMusicAlbum = try await AppleMusicService.shared.findAlbum(
                artist: artist,
                title: title,
                discogsId: discogsId
            )

            if let album = appleMusicAlbum {
                appleMusicTracks = await AppleMusicService.shared.getTracks(for: album)
            }
        } catch {
            appleMusicError = "\(error)"
        }

        isLoadingAppleMusic = false
    }

    private func playTrack(_ track: Track, at index: Int) {
        playingTrackIndex = index
        isPlaying = true
        Task {
            let player = ApplicationMusicPlayer.shared
            player.queue = [track]
            try? await player.play()
        }
    }

    private func togglePlayPause() {
        let player = ApplicationMusicPlayer.shared
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            Task {
                try? await player.play()
                isPlaying = true
            }
        }
    }

    private func stopPlayback() {
        let player = ApplicationMusicPlayer.shared
        player.pause()
        player.queue = []
        isPlaying = false
        playingTrackIndex = nil
    }

    private func openInAppleMusic(_ album: Album) {
        guard let url = album.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func enrich() {
        isEnriching = true
        let objectID = release.objectID
        Task {
            let syncService = SyncService()
            await syncService.enrichSingleRelease(objectID)
            isEnriching = false
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
