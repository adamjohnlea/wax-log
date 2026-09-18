import AppIntents
import CoreData
import CoreSpotlight
import UniformTypeIdentifiers

/// A value-type representation of a `Release` for App Intents and Spotlight.
///
/// Core Data managed objects aren't `Sendable`, so this entity copies the
/// fields it needs as value types. Its identity is `"<discogsId>-<listType>"`,
/// which is stable across CloudKit re-imports (Discogs IDs never change) and
/// unique across the same album appearing in both the collection and wantlist.
///
/// Fields the system may filter, sort, or display are wrapped in `@Property`;
/// only wrapped members are visible to Shortcuts' "Find Records" action. Plain
/// members are used solely to build `displayRepresentation` and `attributeSet`.
struct ReleaseEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Record"
    static let defaultQuery = ReleaseEntityQuery()

    let id: String
    let discogsId: Int64

    @Property(title: "List")
    var listType: String

    @Property(title: "Title")
    var title: String

    /// The raw Discogs artist string, including disambiguation suffixes. Not
    /// exposed to the system — `displayArtist` is the user-facing form — but
    /// kept for Spotlight keywords.
    let artist: String

    @Property(title: "Artist")
    var displayArtist: String

    @Property(title: "Year")
    var year: Int

    @Property(title: "Genre")
    var genre: String

    @Property(title: "Label")
    var label: String

    @Property(title: "Format")
    var format: String

    @Property(title: "Country")
    var country: String

    @Property(title: "Rating")
    var rating: Int

    let imageURL: String?

    /// `@Property` doesn't synthesize a plain-value memberwise initializer, so
    /// this spells one out; the wrappers are already initialized by their
    /// attribute arguments, leaving these assignments to go through the setters.
    init(
        id: String,
        discogsId: Int64,
        listType: String,
        title: String,
        artist: String,
        displayArtist: String,
        year: Int,
        genre: String,
        label: String,
        format: String,
        country: String,
        rating: Int,
        imageURL: String?
    ) {
        self.id = id
        self.discogsId = discogsId
        self.artist = artist
        self.imageURL = imageURL
        self.listType = listType
        self.title = title
        self.displayArtist = displayArtist
        self.year = year
        self.genre = genre
        self.label = label
        self.format = format
        self.country = country
        self.rating = rating
    }

    var displayRepresentation: DisplayRepresentation {
        var parts: [String] = [displayArtist]
        if year > 0 { parts.append(String(year)) }
        let subtitle = parts.joined(separator: " • ")

        if let imageURL, let url = URL(string: imageURL) {
            return DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)", image: .init(url: url))
        }
        return DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    /// Extra Spotlight metadata so searches by artist, genre, or label surface
    /// the album even though the display title is the album name.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = title
        attributes.album = title
        attributes.artist = displayArtist
        attributes.contentDescription = [displayArtist, genre, label, format]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        attributes.keywords = [artist, displayArtist, genre, label, format, country, listType]
            .filter { !$0.isEmpty }
        return attributes
    }
}

extension ReleaseEntity {
    /// Builds an entity from a managed object. Call inside the object's context
    /// `perform` block so property access is thread-safe.
    init(release: Release) {
        let listType = release.listType ?? "collection"
        self.init(
            id: "\(release.discogsId)-\(listType)",
            discogsId: release.discogsId,
            listType: listType,
            title: release.title ?? "Untitled",
            artist: release.artist ?? "",
            displayArtist: release.displayArtist,
            year: Int(release.year),
            genre: release.genre ?? "",
            label: release.label ?? "",
            format: release.format ?? "",
            country: release.country ?? "",
            rating: Int(release.rating),
            imageURL: release.imageURL
        )
    }

    /// Splits an entity ID back into its `(discogsId, listType)` components.
    static func parseID(_ id: String) -> (discogsId: Int64, listType: String)? {
        guard let dash = id.firstIndex(of: "-"),
              let discogsId = Int64(id[..<dash]) else {
            return nil
        }
        return (discogsId, String(id[id.index(after: dash)...]))
    }
}

// MARK: - Shortcuts Filter

/// A `Sendable` description of a single Shortcuts filter term.
///
/// App Intents hands comparator values across an isolation boundary, and
/// `NSPredicate` isn't `Sendable`, so the comparator closures produce this
/// instead and it's converted to a predicate when the fetch runs.
struct ReleaseFilter: Sendable {
    /// The Core Data attribute to filter on.
    let key: String
    let test: Test

    enum Test: Sendable {
        case equalToText(String)
        case containsText(String)
        case hasPrefixText(String)
        case equalToNumber(Int)
        case greaterThanNumber(Int)
        case lessThanNumber(Int)
    }

    var predicate: NSPredicate {
        switch test {
        case .equalToText(let value):
            NSPredicate(format: "%K ==[cd] %@", key, value)
        case .containsText(let value):
            NSPredicate(format: "%K CONTAINS[cd] %@", key, value)
        case .hasPrefixText(let value):
            NSPredicate(format: "%K BEGINSWITH[cd] %@", key, value)
        case .equalToNumber(let value):
            NSPredicate(format: "%K == %@", key, NSNumber(value: value))
        case .greaterThanNumber(let value):
            NSPredicate(format: "%K > %@", key, NSNumber(value: value))
        case .lessThanNumber(let value):
            NSPredicate(format: "%K < %@", key, NSNumber(value: value))
        }
    }
}

// MARK: - Query

/// Locates `ReleaseEntity` instances for Siri, Spotlight, and Shortcuts.
///
/// Three query surfaces, all backed by Core Data:
/// - `entities(for:)` resolves identifiers the system already holds.
/// - `entities(matching:)` (`EntityStringQuery`) powers free-text search using
///   the in-app query language, e.g. `genre:Jazz year:1960..1969`.
/// - `entities(matching:mode:sortedBy:limit:)` (`EntityPropertyQuery`) powers
///   Shortcuts' "Find Records" action, where the system parses the user's
///   filter into comparators that this query executes as a fetch predicate.
/// - `reindexEntities`/`reindexAllEntities` (`IndexedEntityQuery`) let the
///   system ask for Spotlight content to be donated again after it loses or
///   invalidates the index.
struct ReleaseEntityQuery: EntityStringQuery, EntityPropertyQuery, IndexedEntityQuery {
    // Queries run on the main context: result sets are small (capped below) and
    // these run only when Siri/Spotlight/Shortcuts ask, never on a hot path.
    // Async requirements permit a main-actor implementation.

    typealias ComparatorMappingType = ReleaseFilter

    /// Default cap when Shortcuts doesn't supply an explicit limit.
    private static let defaultFetchLimit = 50

    // `nonisolated(unsafe)` is forced here, not chosen: `QueryProperties` and
    // `SortingOptions` aren't `Sendable`, so a stored static of either is a
    // Swift 6 error — but the App Intents build-time validator rejects the
    // computed-property workaround ("expected 'Property' but got
    // 'QueryProperties'"), requiring this exact literal shape. Both are `let`,
    // built once from literals and never mutated, so there's nothing to race on.
    nonisolated(unsafe) static let properties = QueryProperties {
        Property(\.$title) {
            EqualToComparator { ReleaseFilter(key: "title", test: .equalToText($0)) }
            ContainsComparator { ReleaseFilter(key: "title", test: .containsText($0)) }
            HasPrefixComparator { ReleaseFilter(key: "title", test: .hasPrefixText($0)) }
        }
        // Filters against the raw `artist` column, which still contains Discogs
        // disambiguation suffixes — a substring match works either way, and the
        // stripped `displayArtist` form isn't stored.
        Property(\.$displayArtist) {
            EqualToComparator { ReleaseFilter(key: "artist", test: .equalToText($0)) }
            ContainsComparator { ReleaseFilter(key: "artist", test: .containsText($0)) }
            HasPrefixComparator { ReleaseFilter(key: "artist", test: .hasPrefixText($0)) }
        }
        Property(\.$year) {
            EqualToComparator { ReleaseFilter(key: "year", test: .equalToNumber($0)) }
            GreaterThanComparator { ReleaseFilter(key: "year", test: .greaterThanNumber($0)) }
            LessThanComparator { ReleaseFilter(key: "year", test: .lessThanNumber($0)) }
        }
        Property(\.$rating) {
            EqualToComparator { ReleaseFilter(key: "rating", test: .equalToNumber($0)) }
            GreaterThanComparator { ReleaseFilter(key: "rating", test: .greaterThanNumber($0)) }
            LessThanComparator { ReleaseFilter(key: "rating", test: .lessThanNumber($0)) }
        }
        Property(\.$genre) {
            EqualToComparator { ReleaseFilter(key: "genre", test: .equalToText($0)) }
            ContainsComparator { ReleaseFilter(key: "genre", test: .containsText($0)) }
        }
        Property(\.$label) {
            EqualToComparator { ReleaseFilter(key: "label", test: .equalToText($0)) }
            ContainsComparator { ReleaseFilter(key: "label", test: .containsText($0)) }
        }
        Property(\.$format) {
            EqualToComparator { ReleaseFilter(key: "format", test: .equalToText($0)) }
            ContainsComparator { ReleaseFilter(key: "format", test: .containsText($0)) }
        }
        Property(\.$country) {
            EqualToComparator { ReleaseFilter(key: "country", test: .equalToText($0)) }
            ContainsComparator { ReleaseFilter(key: "country", test: .containsText($0)) }
        }
        Property(\.$listType) {
            EqualToComparator { ReleaseFilter(key: "listType", test: .equalToText($0)) }
        }
    }

    nonisolated(unsafe) static let sortingOptions = SortingOptions {
        SortableBy(\.$title)
        SortableBy(\.$displayArtist)
        SortableBy(\.$year)
        SortableBy(\.$rating)
    }

    /// Maps a sortable entity property onto its Core Data attribute name.
    /// `displayArtist` is computed, so it sorts by the stored `artist` column.
    ///
    /// A function rather than a static dictionary: a stored
    /// `[PartialKeyPath<ReleaseEntity>: String]` is global mutable state that
    /// isn't `Sendable`, which Swift 6 rejects.
    private static func sortKey(for keyPath: PartialKeyPath<ReleaseEntity>) -> String? {
        switch keyPath {
        case \ReleaseEntity.$title: "title"
        case \ReleaseEntity.$displayArtist: "artist"
        case \ReleaseEntity.$year: "year"
        case \ReleaseEntity.$rating: "rating"
        default: nil
        }
    }

    @MainActor
    func entities(for identifiers: [ReleaseEntity.ID]) async throws -> [ReleaseEntity] {
        let context = PersistenceController.shared.container.viewContext
        return identifiers.compactMap { identifier -> ReleaseEntity? in
            guard let parsed = ReleaseEntity.parseID(identifier) else { return nil }
            let request = NSFetchRequest<Release>(entityName: "Release")
            request.predicate = NSPredicate(
                format: "discogsId == %lld AND listType == %@",
                parsed.discogsId, parsed.listType
            )
            request.fetchLimit = 1
            guard let release = try? context.fetch(request).first else { return nil }
            return ReleaseEntity(release: release)
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [ReleaseEntity] {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Release>(entityName: "Release")
        request.predicate = SearchService.predicate(from: string)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)]
        request.fetchLimit = Self.defaultFetchLimit
        let releases = (try? context.fetch(request)) ?? []
        return releases.map(ReleaseEntity.init(release:))
    }

    /// Executes a Shortcuts "Find Records" filter. The system only parses the
    /// user's query into `comparators`, `mode`, `sortedBy`, and `limit` — this
    /// method has to honour all four, so they're pushed down into the fetch.
    ///
    /// Stays nonisolated because `EntityQuerySort` isn't `Sendable` and so can't
    /// cross into a main-actor implementation; the sort is reduced to plain
    /// key/direction pairs here and rebuilt on the main actor.
    func entities(
        matching comparators: [ReleaseFilter],
        mode: ComparatorMode,
        sortedBy: [Sort<ReleaseEntity>],
        limit: Int?
    ) async throws -> [ReleaseEntity] {
        let sortKeys: [(key: String, ascending: Bool)] = sortedBy.compactMap { sort in
            guard let key = Self.sortKey(for: sort.by) else { return nil }
            return (key, sort.order == .ascending)
        }
        return await fetch(
            comparators: comparators,
            combineWithAnd: mode == .and,
            sortKeys: sortKeys,
            limit: limit ?? Self.defaultFetchLimit
        )
    }

    @MainActor
    private func fetch(
        comparators: [ReleaseFilter],
        combineWithAnd: Bool,
        sortKeys: [(key: String, ascending: Bool)],
        limit: Int
    ) -> [ReleaseEntity] {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Release>(entityName: "Release")

        if !comparators.isEmpty {
            let predicates = comparators.map(\.predicate)
            request.predicate = combineWithAnd
                ? NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                : NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        }

        // Fall back to newest-first so results stay deterministic when the user
        // didn't choose a sort order.
        request.sortDescriptors = sortKeys.isEmpty
            ? [NSSortDescriptor(keyPath: \Release.dateAdded, ascending: false)]
            : sortKeys.map { NSSortDescriptor(key: $0.key, ascending: $0.ascending) }

        request.fetchLimit = limit
        let releases = (try? context.fetch(request)) ?? []
        return releases.map(ReleaseEntity.init(release:))
    }

    // MARK: - System-driven Spotlight reindexing

    /// Called when the system wants specific records donated again.
    func reindexEntities(
        for identifiers: [ReleaseEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = await SpotlightIndexService.entities(identifiedBy: identifiers)
        try await SpotlightIndexService.donate(entities)
    }

    /// Called when the system has lost or invalidated the index and needs the
    /// whole collection rebuilt. Without this the app would only reseed on a
    /// fresh install, leaving the collection unsearchable until the next sync.
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SpotlightIndexService.replaceAll()
    }

    @MainActor
    func suggestedEntities() async throws -> [ReleaseEntity] {
        let context = PersistenceController.shared.container.viewContext
        let request = Release.collectionFetchRequest()
        request.fetchLimit = 25
        let releases = (try? context.fetch(request)) ?? []
        return releases.map(ReleaseEntity.init(release:))
    }
}
