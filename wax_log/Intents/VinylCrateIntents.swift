import AppIntents

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
    }
}
