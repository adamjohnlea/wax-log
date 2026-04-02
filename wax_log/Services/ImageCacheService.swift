import Foundation
import AppKit

actor ImageCacheService {
    static let shared = ImageCacheService()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let session: URLSession

    // Throttling: 1 request per second
    private var lastRequestTime: Date = .distantPast
    private let minimumInterval: TimeInterval = 1.0

    // Daily cap: 1000 images per day
    private let dailyCap = 1000

    // In-memory cache for quick access
    private var memoryCache = NSCache<NSString, NSImage>()

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("WaxLog/ImageCache", isDirectory: true)

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "WaxLog/1.0 +https://github.com/adamjohnlea/wax-log"]
        session = URLSession(configuration: config)

        memoryCache.countLimit = 200
    }

    // MARK: - Public API

    func image(discogsId: Int64, localImagePath: String?, imageURL: String?) async -> NSImage? {
        // 1. Check memory cache
        let cacheKey = NSString(string: "\(discogsId)")
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        // 2. Check disk cache via localImagePath
        if let localPath = localImagePath {
            let fileURL = cacheDirectory.appendingPathComponent(localPath)
            if let image = NSImage(contentsOf: fileURL) {
                memoryCache.setObject(image, forKey: cacheKey)
                return image
            }
        }

        // 3. Check disk by filename convention
        let filename = "\(discogsId).jpg"
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: fileURL.path) {
            if let image = NSImage(contentsOf: fileURL) {
                memoryCache.setObject(image, forKey: cacheKey)
                return image
            }
        }

        // 4. Download if we have a URL and haven't hit the daily cap
        guard let imageURLString = imageURL, !imageURLString.isEmpty,
              let url = URL(string: imageURLString) else {
            return nil
        }

        guard canDownloadToday() else {
            return nil
        }

        return await downloadAndCache(url: url, discogsId: discogsId)
    }

    func downloadAndCacheImage(discogsId: Int64, imageURL: String?) async -> String? {
        guard let imageURLString = imageURL, !imageURLString.isEmpty,
              let url = URL(string: imageURLString) else {
            return nil
        }

        guard canDownloadToday() else { return nil }

        let filename = "\(discogsId).jpg"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        // Skip if already cached
        guard !fileManager.fileExists(atPath: fileURL.path) else { return filename }

        guard await downloadAndCache(url: url, discogsId: discogsId) != nil else { return nil }

        return filename
    }

    // MARK: - Download

    private func downloadAndCache(url: URL, discogsId: Int64) async -> NSImage? {
        await throttle()
        incrementDailyCount()

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            guard let image = NSImage(data: data) else {
                return nil
            }

            // Save to disk
            let filename = "\(discogsId).jpg"
            let fileURL = cacheDirectory.appendingPathComponent(filename)
            try data.write(to: fileURL, options: .atomic)

            // Cache in memory
            let cacheKey = NSString(string: "\(discogsId)")
            memoryCache.setObject(image, forKey: cacheKey)

            return image
        } catch {
            return nil
        }
    }

    // MARK: - Throttling

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < minimumInterval {
            try? await Task.sleep(for: .seconds(minimumInterval - elapsed))
        }
        lastRequestTime = Date()
    }

    // MARK: - Daily Cap

    private func canDownloadToday() -> Bool {
        resetDailyCountIfNeeded()
        let count = UserDefaults.standard.integer(forKey: "imageDailyCount")
        return count < dailyCap
    }

    private func incrementDailyCount() {
        resetDailyCountIfNeeded()
        let count = UserDefaults.standard.integer(forKey: "imageDailyCount")
        UserDefaults.standard.set(count + 1, forKey: "imageDailyCount")
    }

    private func resetDailyCountIfNeeded() {
        let resetDate = UserDefaults.standard.object(forKey: "imageDailyResetDate") as? Date ?? .distantPast
        if !Calendar.current.isDateInToday(resetDate) {
            UserDefaults.standard.set(0, forKey: "imageDailyCount")
            UserDefaults.standard.set(Date(), forKey: "imageDailyResetDate")
        }
    }

    // MARK: - Additional Images

    /// Download a specific additional image for a release. Returns the local filename.
    func downloadAdditionalImage(discogsId: Int64, imageIndex: Int, url: URL) async -> String? {
        let filename = "\(discogsId)_\(imageIndex).jpg"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        // Skip if already cached
        guard !fileManager.fileExists(atPath: fileURL.path) else { return filename }
        guard canDownloadToday() else { return nil }

        await throttle()
        incrementDailyCount()

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  NSImage(data: data) != nil else {
                return nil
            }
            try data.write(to: fileURL, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    /// Load a cached additional image from disk.
    func additionalImage(discogsId: Int64, imageIndex: Int) -> NSImage? {
        let filename = "\(discogsId)_\(imageIndex).jpg"
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        return NSImage(contentsOf: fileURL)
    }

    /// Check if an additional image is already cached.
    func hasAdditionalImage(discogsId: Int64, imageIndex: Int) -> Bool {
        let filename = "\(discogsId)_\(imageIndex).jpg"
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Delete a cached additional image so it can be re-downloaded.
    func deleteAdditionalImage(discogsId: Int64, imageIndex: Int) {
        let filename = "\(discogsId)_\(imageIndex).jpg"
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: fileURL)
    }

    var remainingDailyDownloads: Int {
        resetDailyCountIfNeeded()
        let count = UserDefaults.standard.integer(forKey: "imageDailyCount")
        return max(0, dailyCap - count)
    }

    // MARK: - Cache Management

    var cacheSize: Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    func clearCache() throws {
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        memoryCache.removeAllObjects()
    }
}
