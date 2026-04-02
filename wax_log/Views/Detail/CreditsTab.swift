import SwiftUI

struct CreditsTab: View {
    @ObservedObject var release: Release
    @State private var isEnriching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let credits = release.decodedCredits, !credits.isEmpty {
                let grouped = Dictionary(grouping: credits) { $0.role }
                let sortedRoles = grouped.keys.sorted()

                ForEach(sortedRoles, id: \.self) { role in
                    GroupBox(role.isEmpty ? "Other" : role) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let artists = grouped[role] {
                                ForEach(Array(artists.enumerated()), id: \.offset) { _, credit in
                                    Text(credit.name)
                                        .font(.callout)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if !release.enriched {
                ContentUnavailableView {
                    Label("No Credits", systemImage: "person.2")
                } description: {
                    Text("Enrich this release to load credits from Discogs.")
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
                    "No Credits Available",
                    systemImage: "person.2",
                    description: Text("This release has no credit data on Discogs.")
                )
            }
        }
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
}
