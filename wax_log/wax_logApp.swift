import SwiftUI

@main
struct wax_logApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            AppCommands()
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
    var body: some Commands {
        // Replace default "New Window" with Sync
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Collection") {
            Button("Sync Collection") {
                NotificationCenter.default.post(name: .syncCollection, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Refresh") {
                NotificationCenter.default.post(name: .refreshCollection, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Enrich All") {
                NotificationCenter.default.post(name: .enrichAll, object: nil)
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
    static let syncCollection = Notification.Name("syncCollection")
    static let refreshCollection = Notification.Name("refreshCollection")
    static let enrichAll = Notification.Name("enrichAll")
    static let switchToListView = Notification.Name("switchToListView")
    static let switchToGridView = Notification.Name("switchToGridView")
}
