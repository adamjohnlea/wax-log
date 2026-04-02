import SwiftUI
import Charts
import CoreData

struct StatisticsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)],
        predicate: NSPredicate(format: "listType == %@", "collection")
    )
    private var releases: FetchedResults<Release>

    var body: some View {
        ScrollView {
            if releases.isEmpty {
                ContentUnavailableView(
                    "No Statistics",
                    systemImage: "chart.bar",
                    description: Text("Sync your collection to see statistics.")
                )
            } else {
                VStack(spacing: 24) {
                    // Summary cards
                    summaryCards

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        GenreChartView(releases: Array(releases))
                        DecadeChartView(releases: Array(releases))
                        FormatChartView(releases: Array(releases))
                        TopArtistsChartView(releases: Array(releases))
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Statistics")
    }

    private var summaryCards: some View {
        HStack(spacing: 16) {
            StatCard(title: "Total Releases", value: "\(releases.count)", icon: "music.note.house")
            StatCard(title: "Artists", value: "\(uniqueArtists)", icon: "person.2")
            StatCard(title: "Genres", value: "\(uniqueGenres)", icon: "guitars")
            StatCard(title: "Avg Rating", value: averageRating, icon: "star")
        }
    }

    private var uniqueArtists: Int {
        Set(releases.compactMap(\.artist).filter { !$0.isEmpty }).count
    }

    private var uniqueGenres: Int {
        Set(releases.compactMap(\.genre).flatMap { $0.components(separatedBy: ", ") }.filter { !$0.isEmpty }).count
    }

    private var averageRating: String {
        let rated = releases.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return "N/A" }
        let avg = Double(rated.reduce(0) { $0 + Int($1.rating) }) / Double(rated.count)
        return String(format: "%.1f", avg)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.title.bold())

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Genre Chart

struct GenreChartView: View {
    let releases: [Release]

    private var genreCounts: [(genre: String, count: Int)] {
        var counts: [String: Int] = [:]
        for release in releases {
            let genres = release.genre?.components(separatedBy: ", ") ?? []
            for genre in genres where !genre.isEmpty {
                counts[genre, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
    }

    var body: some View {
        GroupBox("Top Genres") {
            Chart(genreCounts, id: \.genre) { item in
                BarMark(
                    x: .value("Count", item.count),
                    y: .value("Genre", item.genre)
                )
                .foregroundStyle(.pink.gradient)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: CGFloat(max(genreCounts.count, 1) * 28 + 20))
        }
    }
}

// MARK: - Decade Chart

struct DecadeChartView: View {
    let releases: [Release]

    private var decadeCounts: [(decade: String, count: Int)] {
        var counts: [Int: Int] = [:]
        for release in releases where release.year > 0 {
            let decade = (Int(release.year) / 10) * 10
            counts[decade, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }.map { ("\($0.key)s", $0.value) }
    }

    var body: some View {
        GroupBox("By Decade") {
            Chart(decadeCounts, id: \.decade) { item in
                BarMark(
                    x: .value("Decade", item.decade),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(.blue.gradient)
                .annotation(position: .top) {
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 200)
        }
    }
}

// MARK: - Format Chart

struct FormatChartView: View {
    let releases: [Release]

    private var formatCounts: [(format: String, count: Int)] {
        var counts: [String: Int] = [:]
        for release in releases {
            let format = release.format ?? "Unknown"
            guard !format.isEmpty else { continue }
            counts[format, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }
    }

    var body: some View {
        GroupBox("By Format") {
            Chart(formatCounts, id: \.format) { item in
                SectorMark(
                    angle: .value("Count", item.count),
                    innerRadius: .ratio(0.5),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("Format", item.format))
                .annotation(position: .overlay) {
                    if item.count > releases.count / 10 {
                        Text("\(item.count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 200)
        }
    }
}

// MARK: - Top Artists Chart

struct TopArtistsChartView: View {
    let releases: [Release]

    private var artistCounts: [(artist: String, count: Int)] {
        var counts: [String: Int] = [:]
        for release in releases {
            let artist = release.artist ?? "Unknown"
            guard !artist.isEmpty else { continue }
            counts[artist, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
    }

    var body: some View {
        GroupBox("Top Artists") {
            Chart(artistCounts, id: \.artist) { item in
                BarMark(
                    x: .value("Count", item.count),
                    y: .value("Artist", item.artist)
                )
                .foregroundStyle(.orange.gradient)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: CGFloat(max(artistCounts.count, 1) * 28 + 20))
        }
    }
}
