import SwiftUI

struct ReleaseDetailView: View {
    @ObservedObject var release: Release
    @State private var selectedTab: DetailTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            releaseHeader
                .padding()

            Divider()

            // Tab bar
            Picker("Tab", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Tab content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .overview:
                        OverviewTab(release: release)
                    case .tracks:
                        TracksTab(release: release)
                    case .credits:
                        CreditsTab(release: release)
                    case .notes:
                        NotesTab(release: release)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(release.title ?? "Release")
    }

    // MARK: - Header

    private var releaseHeader: some View {
        HStack(alignment: .top, spacing: 20) {
            AlbumArtView(release: release, size: 160)

            VStack(alignment: .leading, spacing: 6) {
                Text(release.title ?? "Untitled")
                    .font(.title.bold())

                Text(release.artist ?? "Unknown Artist")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Spacer()

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
                .foregroundStyle(.secondary)

                if release.rating > 0 {
                    Text(release.displayRating)
                        .font(.callout)
                }
            }

            Spacer()
        }
        .frame(height: 160)
    }
}

// MARK: - Tab Enum

enum DetailTab: CaseIterable {
    case overview, tracks, credits, notes

    var label: String {
        switch self {
        case .overview: "Overview"
        case .tracks: "Tracks"
        case .credits: "Credits"
        case .notes: "Notes"
        }
    }
}

// MARK: - Overview Tab

struct OverviewTab: View {
    @ObservedObject var release: Release

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Details") {
                metadataGrid
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if release.mediaCondition != nil || release.sleeveCondition != nil {
                GroupBox("Condition") {
                    VStack(alignment: .leading, spacing: 4) {
                        if let media = release.mediaCondition, !media.isEmpty {
                            LabeledContent("Media", value: media)
                        }
                        if let sleeve = release.sleeveCondition, !sleeve.isEmpty {
                            LabeledContent("Sleeve", value: sleeve)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let identifiers = release.decodedIdentifiers, !identifiers.isEmpty {
                GroupBox("Identifiers") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        ForEach(Array(identifiers.enumerated()), id: \.offset) { _, identifier in
                            GridRow {
                                Text(identifier.type)
                                    .foregroundStyle(.secondary)
                                Text(identifier.value)
                            }
                        }
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let notes = release.notes, !notes.isEmpty {
                GroupBox("Release Notes") {
                    Text(notes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            if release.year > 0 {
                metadataRow("Year", release.displayYear)
            }
            if let label = release.label, !label.isEmpty {
                metadataRow("Label", label)
            }
            if let format = release.format, !format.isEmpty {
                metadataRow("Format", format)
            }
            if let genre = release.genre, !genre.isEmpty {
                metadataRow("Genre", genre)
            }
            if let style = release.style, !style.isEmpty {
                metadataRow("Style", style)
            }
            if let country = release.country, !country.isEmpty {
                metadataRow("Country", country)
            }
            if let barcode = release.barcode, !barcode.isEmpty {
                metadataRow("Barcode", barcode)
            }
            metadataRow("Discogs ID", String(release.discogsId))
            metadataRow("List", release.isCollection ? "Collection" : "Wantlist")
            if let dateAdded = release.dateAdded {
                metadataRow("Added", dateAdded.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
