import Foundation
import MusicKit

actor AppleMusicService {
    static let shared = AppleMusicService()

    // Cache: discogsId -> Apple Music album ID
    private var matchCache: [Int64: String] = [:]

    private init() {}

    // MARK: - Authorization

    var isAuthorized: Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    func requestAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()
        return status == .authorized
    }

    // MARK: - Album Matching

    /// Attempts to find an Apple Music album matching a release, first by barcode (UPC), then by artist + title.
    func findAlbum(barcode: String?, artist: String?, title: String?, discogsId: Int64) async -> Album? {
        // Check cache
        if let cachedId = matchCache[discogsId] {
            return await fetchAlbumById(cachedId)
        }

        // 1. Try UPC/barcode match (most accurate)
        if let barcode = barcode, !barcode.isEmpty {
            if let album = await searchByUPC(barcode) {
                matchCache[discogsId] = album.id.rawValue
                return album
            }
        }

        // 2. Fall back to artist + title search
        if let artist = artist, let title = title, !artist.isEmpty, !title.isEmpty {
            if let album = await searchByArtistTitle(artist: artist, title: title) {
                matchCache[discogsId] = album.id.rawValue
                return album
            }
        }

        return nil
    }

    // MARK: - Search Methods

    private func searchByUPC(_ upc: String) async -> Album? {
        do {
            var request = MusicCatalogSearchRequest(term: upc, types: [Album.self])
            request.limit = 1
            let response = try await request.response()
            return response.albums.first
        } catch {
            return nil
        }
    }

    private func searchByArtistTitle(artist: String, title: String) async -> Album? {
        do {
            // Clean up artist name (remove featuring, etc.)
            let cleanArtist = artist.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? artist
            let query = "\(cleanArtist) \(title)"

            var request = MusicCatalogSearchRequest(term: query, types: [Album.self])
            request.limit = 5
            let response = try await request.response()

            // Try to find a good match
            let titleLower = title.lowercased()
            let artistLower = cleanArtist.lowercased()

            // Prefer exact title match
            if let match = response.albums.first(where: {
                $0.title.lowercased() == titleLower &&
                $0.artistName.lowercased().contains(artistLower)
            }) {
                return match
            }

            // Accept contains match
            if let match = response.albums.first(where: {
                $0.title.lowercased().contains(titleLower) ||
                titleLower.contains($0.title.lowercased())
            }) {
                return match
            }

            // Return first result as last resort
            return response.albums.first
        } catch {
            return nil
        }
    }

    private func fetchAlbumById(_ id: String) async -> Album? {
        do {
            let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(rawValue: id))
            let response = try await request.response()
            return response.items.first
        } catch {
            return nil
        }
    }

    // MARK: - Tracks

    func getTracks(for album: Album) async -> [Track]? {
        do {
            let detailedAlbum = try await album.with([.tracks])
            guard let tracks = detailedAlbum.tracks else { return nil }
            return Array(tracks)
        } catch {
            return nil
        }
    }
}
