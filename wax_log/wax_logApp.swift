import SwiftUI
import AppIntents

@main
struct wax_logApp: App {
    let persistenceController = PersistenceController.shared
    @State private var appModel: AppModel

    init() {
        let model = AppModel(persistenceController: .shared)
        _appModel = State(initialValue: model)
        // Register the same instance for App Intents dependency injection so
        // intents can drive navigation (open a release, surprise me, etc.).
        AppDependencyManager.shared.add(dependency: model)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(appModel)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            AppCommands(appModel: appModel)
        }

        Settings {
            SettingsView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .frame(width: 500, height: 450)
        }
    }
}

// MARK: - Menu Bar Commands

struct AppCommands: Commands {
    let appModel: AppModel

    var body: some Commands {
        // Replace default "New Window" with Sync
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Collection") {
            Button("Sync Collection") {
                appModel.syncCollection()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Refresh") {
                appModel.refreshCollection()
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Enrich All") {
                appModel.enrichAll()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Divider()

            Button("List View") {
                NotificationCenter.default.post(name: .switchToListView, object: nil)
            }
            .keyboardShortcut("1", modifiers: [.command, .control])

            Button("Grid View") {
                NotificationCenter.default.post(name: .switchToGridView, object: nil)
            }
            .keyboardShortcut("2", modifiers: [.command, .control])
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    // View-mode toggles remain notification-based because they target a single
    // CollectionView's local state, not app-wide navigation.
    static let switchToListView = Notification.Name("switchToListView")
    static let switchToGridView = Notification.Name("switchToGridView")
}
