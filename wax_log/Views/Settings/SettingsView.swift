import SwiftUI
import MusicKit

struct SettingsView: View {
    @State private var discogsUsername: String = ""
    @State private var discogsToken: String = ""
    @State private var showingToken = false
    @State private var saveStatus: SaveStatus?
    @State private var musicAuthStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                discogsSection
                appleMusicSection
                aboutSection
            }
            .padding()
        }
        .navigationTitle("Settings")
        .onAppear {
            loadCredentials()
            musicAuthStatus = MusicAuthorization.currentStatus
        }
    }

    // MARK: - Discogs

    private var discogsSection: some View {
        GroupBox("Discogs Account") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Username")
                        .font(.callout.weight(.medium))
                    TextField("Your Discogs username", text: $discogsUsername)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal Access Token")
                        .font(.callout.weight(.medium))

                    HStack {
                        if showingToken {
                            TextField("Paste your token here", text: $discogsToken)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Paste your token here", text: $discogsToken)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            showingToken.toggle()
                        } label: {
                            Image(systemName: showingToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    Text("Generate a token at discogs.com/settings/developers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if let status = saveStatus {
                        Label(status.message, systemImage: status.isSuccess ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(status.isSuccess ? .green : .red)
                    }

                    if let result = connectionTestResult {
                        Label(result.message, systemImage: result.isSuccess ? "checkmark.circle" : "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(result.isSuccess ? .green : .red)
                    }

                    Spacer()

                    Button {
                        testConnection()
                    } label: {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(discogsUsername.isEmpty || discogsToken.isEmpty || isTestingConnection)

                    Button("Save") {
                        saveCredentials()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(discogsUsername.isEmpty || discogsToken.isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Apple Music

    private var appleMusicSection: some View {
        GroupBox("Apple Music") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MusicKit Access")
                        .font(.callout.weight(.medium))

                    switch musicAuthStatus {
                    case .authorized:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .denied:
                        Text("Denied. Enable in System Settings > Privacy > Media & Apple Music.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    case .restricted:
                        Text("Restricted on this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .notDetermined:
                        Text("Not yet requested.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }

                Spacer()

                if musicAuthStatus == .notDetermined {
                    Button("Connect") {
                        Task {
                            _ = await AppleMusicService.shared.requestAuthorization()
                            musicAuthStatus = MusicAuthorization.currentStatus
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else if musicAuthStatus == .denied {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media")!)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        GroupBox("About") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Wax Log")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("Version 1.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("A native macOS app for managing your Discogs vinyl collection. Local-first with iCloud sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 16) {
                    Text("Data from Discogs.com")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Playback via Apple Music")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func loadCredentials() {
        discogsUsername = KeychainService.load(.discogsUsername) ?? ""
        discogsToken = KeychainService.load(.discogsToken) ?? ""
    }

    private func saveCredentials() {
        do {
            try KeychainService.save(discogsUsername, for: .discogsUsername)
            try KeychainService.save(discogsToken, for: .discogsToken)
            saveStatus = SaveStatus(message: "Saved", isSuccess: true)
        } catch {
            saveStatus = SaveStatus(message: error.localizedDescription, isSuccess: false)
        }

        connectionTestResult = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = nil
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        // Save first so the client can use the credentials
        try? KeychainService.save(discogsUsername, for: .discogsUsername)
        try? KeychainService.save(discogsToken, for: .discogsToken)

        Task {
            do {
                let response = try await DiscogsClient.shared.getCollectionReleases(username: discogsUsername, page: 1, perPage: 1)
                connectionTestResult = ConnectionTestResult(
                    message: "Connected! \(response.pagination.items) releases found.",
                    isSuccess: true
                )
            } catch {
                connectionTestResult = ConnectionTestResult(
                    message: error.localizedDescription,
                    isSuccess: false
                )
            }
            isTestingConnection = false
        }
    }

    private struct SaveStatus {
        let message: String
        let isSuccess: Bool
    }

    private struct ConnectionTestResult {
        let message: String
        let isSuccess: Bool
    }
}
