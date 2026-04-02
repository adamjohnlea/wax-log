import SwiftUI
import CoreData

struct RandomizerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var randomRelease: Release?
    @State private var isAnimating = false

    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "listType == %@", "collection")
    )
    private var releases: FetchedResults<Release>

    var body: some View {
        VStack(spacing: 24) {
            if releases.isEmpty {
                ContentUnavailableView(
                    "No Releases",
                    systemImage: "dice",
                    description: Text("Sync your collection first to use the randomizer.")
                )
            } else if let release = randomRelease {
                // Selected release
                VStack(spacing: 20) {
                    AlbumArtView(release: release, size: 280)
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                        .scaleEffect(isAnimating ? 0.95 : 1.0)
                        .animation(.spring(duration: 0.3), value: isAnimating)

                    VStack(spacing: 6) {
                        Text(release.title ?? "Untitled")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)

                        Text(release.displayArtist)
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            if release.year > 0 {
                                Label(release.displayYear, systemImage: "calendar")
                            }
                            if let format = release.format, !format.isEmpty {
                                Label(format, systemImage: "opticaldisc")
                            }
                            if let genre = release.genre, !genre.isEmpty {
                                Label(genre, systemImage: "music.note")
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.tertiary)

                        if release.rating > 0 {
                            Text(release.displayRating)
                                .font(.title3)
                                .padding(.top, 4)
                        }
                    }

                    HStack(spacing: 16) {
                        Button {
                            pickRandom()
                        } label: {
                            Label("Surprise Me", systemImage: "dice")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        NavigationLink(value: release.objectID) {
                            Label("View Details", systemImage: "info.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            } else {
                // Initial state
                VStack(spacing: 16) {
                    Image(systemName: "dice")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)

                    Text("What should you listen to?")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Button {
                        pickRandom()
                    } label: {
                        Label("Surprise Me", systemImage: "dice")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Randomizer")
    }

    private func pickRandom() {
        guard !releases.isEmpty else { return }
        isAnimating = true
        withAnimation(.easeInOut(duration: 0.15)) {
            randomRelease = releases.randomElement()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isAnimating = false
        }
    }
}
