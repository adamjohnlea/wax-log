import AppIntents
import MusicKit

/// Picks a random record from the user's collection, opens the app, and
/// navigates to it. Backed by `AppModel`, which is registered with
/// `AppDependencyManager` in `wax_logApp`.
struct SurpriseMeIntent: AppIntent {
    static var title: LocalizedStringResource = "Surprise Me"
    static var description = IntentDescription("Pick a random record from your collection and open it.")

    /// Bring the app to the foreground so the chosen release is visible.
    static var openAppWhenRun = true

    @Dependency private var appModel: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let title = appModel.surpriseMe() else {
            return .result(dialog: "Your collection is empty. Sync from Discogs first.")
        }
        return .result(dialog: "How about \(title)?")
    }
}

/// Opens a specific record in the app. Used both as a Shortcuts action and by
/// Spotlight to open a record from a search result.
struct OpenReleaseIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Record"

    @Parameter(title: "Record")
    var target: ReleaseEntity

    @Dependency private var appModel: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        appModel.openRelease(discogsId: target.discogsId, listType: target.listType)
        return .result()
    }
}

/// Searches the collection and wantlist using the in-app query language
/// (e.g. `genre:Jazz year:1960..1969`, or a plain artist/title).
struct FindReleasesIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Records"
    static var description = IntentDescription("Search your collection and wantlist.")

    @Parameter(title: "Search", description: #"An artist or title, or a query like "genre:Jazz year:1960..1969""#)
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[ReleaseEntity]> & ProvidesDialog {
        let results = try await ReleaseEntityQuery().entities(matching: query)
        let dialog: IntentDialog = results.isEmpty
            ? "No records matched \(query)."
            : "Found \(results.count) record\(results.count == 1 ? "" : "s")."
        return .result(value: results, dialog: dialog)
    }
}

/// Searches Discogs for a record and adds the top match to the wantlist.
struct AddToWantlistIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Wantlist"
    static var description = IntentDescription("Search Discogs and add the top match to your wantlist.")

    @Parameter(title: "Record", description: "An artist and/or album title to search for")
    var query: String

    @Dependency private var appModel: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let title = try await appModel.addToWantlist(matching: query) else {
            return .result(dialog: "I couldn't find \"\(query)\" on Discogs.")
        }
        return .result(dialog: "Added \(title) to your wantlist.")
    }
}

/// Matches a record to Apple Music and plays the album.
struct PlayRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Record"
    static var description = IntentDescription("Find a record on Apple Music and play the album.")

    @Parameter(title: "Record")
    var target: ReleaseEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Ensure Apple Music access.
        if await !AppleMusicService.shared.isAuthorized {
            guard await AppleMusicService.shared.requestAuthorization() else {
                return .result(dialog: "Open Vinyl Crate and connect Apple Music, then try again.")
            }
        }

        // Reuse the app's matching logic (and its cache).
        let album = try await AppleMusicService.shared.findAlbum(
            artist: target.artist,
            title: target.title,
            discogsId: target.discogsId
        )
        guard let album else {
            return .result(dialog: "I couldn't find \(target.title) on Apple Music.")
        }

        let player = ApplicationMusicPlayer.shared
        player.queue = [album]
        try await player.play()
        return .result(dialog: "Playing \(album.title).")
    }
}

/// Reports a summary of the collection (counts and average rating).
struct CollectionStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Collection Stats"
    static var description = IntentDescription("Get a summary of your record collection.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = CollectionStats.current().spokenSummary
        return .result(value: summary, dialog: "\(summary)")
    }
}

/// Exposes the app's intents to Siri and the Shortcuts app.
///
/// Note: macOS doesn't surface pre-configured App Shortcuts system-wide the way
/// iOS does, but these intents appear in the Shortcuts app, where the user can
/// build a shortcut and assign a Siri phrase to it.
struct VinylCrateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SurpriseMeIntent(),
            phrases: [
                "Surprise me with a record in \(.applicationName)",
                "What should I play in \(.applicationName)"
            ],
            shortTitle: "Surprise Me",
            systemImageName: "dice"
        )
        AppShortcut(
            intent: FindReleasesIntent(),
            phrases: [
                "Find a record in \(.applicationName)",
                "Search my records in \(.applicationName)"
            ],
            shortTitle: "Find Records",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: AddToWantlistIntent(),
            phrases: [
                "Add a record to my wantlist in \(.applicationName)",
                "Add to my \(.applicationName) wantlist"
            ],
            shortTitle: "Add to Wantlist",
            systemImageName: "heart"
        )
        AppShortcut(
            intent: CollectionStatsIntent(),
            phrases: [
                "How many records do I have in \(.applicationName)",
                "My \(.applicationName) collection stats"
            ],
            shortTitle: "Collection Stats",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: PlayRecordIntent(),
            phrases: [
                "Play a record in \(.applicationName)",
                "Play a record from \(.applicationName)"
            ],
            shortTitle: "Play Record",
            systemImageName: "play.circle"
        )
    }
}
