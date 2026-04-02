import Foundation
import MusicKit

actor AppleMusicService {
    static let shared = AppleMusicService()

    // Cache: discogsId -> Apple Music album ID (nil = searched but not found)
    private var matchCache: [Int64: String?] = [:]

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

    /// Finds an Apple Music album. Throws on API errors so callers can display them.
    func findAlbum(artist: String?, title: String?, discogsId: Int64) async throws -> Album? {
        // Check cache (including negative cache)
        if let cached = matchCache[discogsId] {
            if let albumId = cached {
                return await fetchAlbumById(albumId)
            }
            return nil
        }

        guard let artist = artist, let title = title, !artist.isEmpty, !title.isEmpty else {
            return nil
        }

        let cleanArtist = cleanArtistName(artist)

        guard !cleanArtist.isEmpty, cleanArtist.lowercased() != "various" else {
            matchCache[discogsId] = .some(nil)
            return nil
        }

        // Try search with artist + title
        if let album = try await searchAlbumThrowing(artist: cleanArtist, title: title) {
            matchCache[discogsId] = .some(album.id.rawValue)
            return album
        }

        // Try combined query as fallback
        if let album = try await searchAlbumThrowing(artist: nil, title: "\(cleanArtist) \(title)") {
            matchCache[discogsId] = .some(album.id.rawValue)
            return album
        }

        matchCache[discogsId] = .some(nil)
        return nil
    }

    // MARK: - Search

    /// Search Apple Music. Throws on error so callers can surface the problem.
    func searchAlbumThrowing(artist: String?, title: String) async throws -> Album? {
        let query: String
        if let artist {
            query = "\(artist) \(title)"
        } else {
            query = title
        }

        var request = MusicCatalogSearchRequest(term: query, types: [Album.self])
        request.limit = 10
        let response = try await request.response()

        let albums = Array(response.albums)
        guard !albums.isEmpty else { return nil }

            let titleLower = title.lowercased()
            let artistLower = artist?.lowercased()

            // Best: exact title + artist match
            if let artistLower {
                if let match = albums.first(where: {
                    $0.title.lowercased() == titleLower &&
                    $0.artistName.lowercased().contains(artistLower)
                }) {
                    return match
                }
            }

            // Good: exact title match (any artist)
            if let match = albums.first(where: {
                $0.title.lowercased() == titleLower
            }) {
                return match
            }

            // OK: title contains or is contained
            if let match = albums.first(where: {
                $0.title.lowercased().contains(titleLower) ||
                titleLower.contains($0.title.lowercased())
            }) {
                return match
            }

            // Last resort: return top result
        return albums.first
    }

    // MARK: - Artist Name Cleaning

    private func cleanArtistName(_ name: String) -> String {
        // Take first artist from comma-separated list
        var clean = name.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? name

        // Remove Discogs disambiguation like "(2)", "(3)" at end
        if let range = clean.range(of: #"\s*\(\d+\)\s*$"#, options: .regularExpression) {
            clean = String(clean[clean.startIndex..<range.lowerBound])
        }

        // Remove "The " prefix variations for better matching
        // (Apple Music sometimes stores without "The")
        // Don't remove it - just return as-is, the search is fuzzy enough

        return clean.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Fetch by ID

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

    func clearCache() {
        matchCache.removeAll()
    }
}
