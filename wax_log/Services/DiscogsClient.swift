import Foundation

actor DiscogsClient {
    static let shared = DiscogsClient()

    private let baseURL = URL(string: "https://api.discogs.com")!
    private let session: URLSession
    private let userAgent = "WaxLog/1.0 +https://github.com/adamjohnlea/wax-log"

    // Rate limiting state
    private var rateLimitRemaining: Int = 60
    private var lastRequestTime: Date = .distantPast
    private let minimumRequestInterval: TimeInterval = 1.0

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Collection & Wantlist

    func getCollectionReleases(username: String, page: Int = 1, perPage: Int = 100) async throws -> PaginatedResponse<CollectionRelease> {
        let url = baseURL.appendingPathComponent("/users/\(username)/collection/folders/0/releases")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "sort", value: "added"),
            URLQueryItem(name: "sort_order", value: "desc")
        ]
        return try await request(url: components.url!)
    }

    func getWantlistReleases(username: String, page: Int = 1, perPage: Int = 100) async throws -> PaginatedResponse<WantlistRelease> {
        let url = baseURL.appendingPathComponent("/users/\(username)/wants")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        return try await request(url: components.url!)
    }

    // MARK: - Release Detail (for enrichment)

    func getReleaseDetail(releaseId: Int) async throws -> ReleaseDetail {
        let url = baseURL.appendingPathComponent("/releases/\(releaseId)")
        return try await request(url: url)
    }

    // MARK: - Search

    func search(query: String, type: String = "release", page: Int = 1, perPage: Int = 50) async throws -> SearchResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/database/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        return try await request(url: components.url!)
    }

    // MARK: - Add to Collection / Wantlist

    /// Add a release to the user's collection (folder 1 = Uncategorized).
    func addToCollection(username: String, releaseId: Int) async throws {
        let url = baseURL.appendingPathComponent("/users/\(username)/collection/folders/1/releases/\(releaseId)")
        try await sendRequest(url: url, method: "POST")
    }

    /// Add a release to the user's wantlist.
    func addToWantlist(username: String, releaseId: Int) async throws {
        let url = baseURL.appendingPathComponent("/users/\(username)/wants/\(releaseId)")
        try await sendRequest(url: url, method: "PUT")
    }

    // MARK: - Edit Collection Item

    /// Set the rating for a release (1-5, or 0 to remove).
    /// Uses PUT /releases/{release_id}/rating/{username}
    func setRating(username: String, releaseId: Int, rating: Int) async throws {
        let url = baseURL.appendingPathComponent("/releases/\(releaseId)/rating/\(username)")
        if rating == 0 {
            try await sendRequest(url: url, method: "DELETE")
        } else {
            let body = ["rating": rating]
            try await sendRequest(url: url, method: "PUT", body: body)
        }
    }

    /// Edit a custom field value on a collection instance.
    /// field_id 1 = Media Condition, 2 = Sleeve Condition, 3 = Notes
    func editInstanceField(username: String, folderId: Int = 0, releaseId: Int, instanceId: Int, fieldId: Int, value: String) async throws {
        let url = baseURL.appendingPathComponent("/users/\(username)/collection/folders/\(folderId)/releases/\(releaseId)/instances/\(instanceId)/fields/\(fieldId)")
        try await sendRequest(url: url, method: "POST", body: ["value": value])
    }

    /// Get collection instances for a release to find the instance_id.
    func getCollectionInstances(username: String, releaseId: Int) async throws -> PaginatedResponse<CollectionRelease> {
        let url = baseURL.appendingPathComponent("/users/\(username)/collection/releases/\(releaseId)")
        return try await request(url: url)
    }

    // MARK: - Core Request

    private func request<T: Decodable>(url: URL, retryCount: Int = 0) async throws -> T {
        try await throttle()

        guard let token = KeychainService.load(.discogsToken) else {
            throw DiscogsError.noToken
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscogsError.invalidResponse
        }

        updateRateLimit(from: httpResponse)

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)

        case 401:
            throw DiscogsError.unauthorized

        case 404:
            throw DiscogsError.notFound

        case 429:
            if retryCount < 3 {
                let backoff = pow(2.0, Double(retryCount)) * 1.0
                try await Task.sleep(for: .seconds(backoff))
                return try await request(url: url, retryCount: retryCount + 1)
            }
            throw DiscogsError.rateLimited

        default:
            throw DiscogsError.httpError(httpResponse.statusCode)
        }
    }

    /// Send a request that doesn't return a decoded body (POST/PUT/DELETE).
    private func sendRequest(url: URL, method: String, body: [String: Any]? = nil, retryCount: Int = 0) async throws {
        try await throttle()

        guard let token = KeychainService.load(.discogsToken) else {
            throw DiscogsError.noToken
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (_, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscogsError.invalidResponse
        }

        updateRateLimit(from: httpResponse)

        switch httpResponse.statusCode {
        case 200...299, 204:
            return

        case 401:
            throw DiscogsError.unauthorized

        case 404:
            throw DiscogsError.notFound

        case 429:
            if retryCount < 3 {
                let backoff = pow(2.0, Double(retryCount)) * 1.0
                try await Task.sleep(for: .seconds(backoff))
                try await sendRequest(url: url, method: method, body: body, retryCount: retryCount + 1)
                return
            }
            throw DiscogsError.rateLimited

        default:
            throw DiscogsError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - Rate Limiting

    private func throttle() async throws {
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < minimumRequestInterval {
            let delay = minimumRequestInterval - elapsed
            try await Task.sleep(for: .seconds(delay))
        }

        if rateLimitRemaining <= 1 {
            try await Task.sleep(for: .seconds(2.0))
        }

        lastRequestTime = Date()
    }

    private func updateRateLimit(from response: HTTPURLResponse) {
        if let remaining = response.value(forHTTPHeaderField: "X-Discogs-Ratelimit-Remaining"),
           let value = Int(remaining) {
            rateLimitRemaining = value
        }
    }
}

// MARK: - Errors

nonisolated enum DiscogsError: LocalizedError {
    case noToken
    case invalidResponse
    case unauthorized
    case notFound
    case rateLimited
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "No Discogs token configured. Add your token in Settings."
        case .invalidResponse:
            return "Invalid response from Discogs."
        case .unauthorized:
            return "Discogs token is invalid or expired."
        case .notFound:
            return "Resource not found on Discogs."
        case .rateLimited:
            return "Discogs rate limit exceeded. Please wait and try again."
        case .httpError(let code):
            return "Discogs API error (HTTP \(code))."
        }
    }
}

// MARK: - Response Models

nonisolated struct Pagination: Decodable, Sendable {
    let page: Int
    let pages: Int
    let perPage: Int
    let items: Int
}

nonisolated struct PaginatedResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let pagination: Pagination
    let releases: [T]?
    let wants: [T]?

    var items: [T] {
        releases ?? wants ?? []
    }
}

nonisolated struct CollectionRelease: Decodable, Sendable {
    let id: Int
    let instanceId: Int
    let rating: Int
    let dateAdded: String
    let basicInformation: BasicInformation
    let notes: [NoteField]?

    nonisolated struct NoteField: Decodable, Sendable {
        let fieldId: Int
        let value: String
    }
}

nonisolated struct WantlistRelease: Decodable, Sendable {
    let id: Int
    let rating: Int
    let dateAdded: String
    let basicInformation: BasicInformation
    let notes: String?
}

nonisolated struct BasicInformation: Decodable, Sendable {
    let id: Int
    let title: String
    let year: Int
    let resourceUrl: String
    let thumb: String
    let coverImage: String
    let formats: [Format]?
    let labels: [Label]?
    let artists: [Artist]?
    let genres: [String]?
    let styles: [String]?

    nonisolated struct Format: Decodable, Sendable {
        let name: String
        let qty: String?
        let descriptions: [String]?
    }

    nonisolated struct Label: Decodable, Sendable {
        let name: String
        let catno: String?
    }

    nonisolated struct Artist: Decodable, Sendable {
        let name: String
        let id: Int
    }
}

nonisolated struct ReleaseDetail: Decodable, Sendable {
    let id: Int
    let title: String
    let year: Int
    let artists: [BasicInformation.Artist]?
    let labels: [BasicInformation.Label]?
    let formats: [BasicInformation.Format]?
    let genres: [String]?
    let styles: [String]?
    let country: String?
    let notes: String?
    let tracklist: [Track]?
    let extraartists: [CreditArtist]?
    let identifiers: [Identifier]?
    let images: [Image]?

    nonisolated struct Track: Decodable, Sendable {
        let position: String?
        let title: String
        let duration: String?
        let type: String?

        enum CodingKeys: String, CodingKey {
            case position, title, duration
            case type = "type_"
        }
    }

    nonisolated struct CreditArtist: Decodable, Sendable {
        let name: String
        let role: String?
    }

    nonisolated struct Identifier: Decodable, Sendable {
        let type: String?
        let value: String?
        let description: String?
    }

    nonisolated struct Image: Decodable, Sendable {
        let type: String
        let uri: String
        let uri150: String
        let resourceUrl: String
        let width: Int
        let height: Int
    }
}

nonisolated struct SearchResponse: Decodable, Sendable {
    let pagination: Pagination
    let results: [SearchResult]
}

nonisolated struct SearchResult: Decodable, Sendable {
    let id: Int
    let title: String
    let year: String?
    let thumb: String?
    let coverImage: String?
    let type: String
    let resourceUrl: String
    let country: String?
    let format: [String]?
    let label: [String]?
    let genre: [String]?
    let style: [String]?
    let barcode: [String]?
}
