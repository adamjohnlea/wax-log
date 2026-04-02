# My Music Collection — macOS App Design Document

## Overview

A fully native macOS 26 app that mirrors the feature set of `adamjohnlea/my-music-collection` (PHP/web version), built with SwiftUI and backed by Core Data + CloudKit for iCloud sync. Local-first: all browsing is from the local database. Discogs API is only hit during sync operations.

---

## Tech Stack

| Layer | Choice | Rationale |
|---|---|---|
| UI | SwiftUI | Native macOS look and feel |
| Data | Core Data | iCloud sync via CloudKit |
| Sync | `NSPersistentCloudKitContainer` | Free iCloud sync, conflict resolution handled by Apple |
| Networking | `URLSession` + async/await | Native, no dependencies |
| Image cache | FileManager + disk cache | Same as web version — local image files |
| Keychain | `Security` framework | Store Discogs token securely |

---

## Core Data Schema

### Release entity
- `discogsId` Int64
- `title` String
- `artist` String
- `year` Int32
- `label` String
- `format` String
- `genre` String
- `style` String
- `country` String
- `barcode` String?
- `notes` String?
- `personalNotes` String?
- `rating` Int16
- `mediaCondition` String?
- `sleeveCondition` String?
- `dateAdded` Date
- `enriched` Bool
- `tracklist` String? (JSON blob)
- `credits` String? (JSON blob)
- `imageURL` String?
- `localImagePath` String?
- `listType` String (`collection` or `wantlist`)

### SmartCollection entity
- `name` String
- `query` String
- `createdAt` Date

### SyncState entity
- `lastRefreshDate` Date?
- `imageDailyCount` Int32
- `imageDailyResetDate` Date?

---

## App Structure

```
MyMusicCollection/
├── App/
│   └── MyMusicCollectionApp.swift       # @main, CoreData stack setup
├── Persistence/
│   ├── PersistenceController.swift      # NSPersistentCloudKitContainer
│   └── MyMusicCollection.xcdatamodeld  # Core Data schema
├── Models/
│   └── Release+Extensions.swift        # Helpers on NSManagedObject subclasses
├── Services/
│   ├── DiscogsClient.swift             # URLSession wrapper, rate limiting, retries
│   ├── SyncService.swift               # Initial sync, refresh, enrich
│   ├── ImageCacheService.swift         # Download + disk cache, 1 req/s throttle
│   └── SearchService.swift             # NSPredicate-based search
├── Views/
│   ├── ContentView.swift               # Root: NavigationSplitView
│   ├── Sidebar/
│   │   ├── SidebarView.swift           # Collections, Wantlist, Smart Collections
│   │   └── SmartCollectionRow.swift
│   ├── Collection/
│   │   ├── CollectionView.swift        # Grid or list of releases
│   │   ├── ReleaseCard.swift           # Album art + metadata card
│   │   └── ReleaseDetailView.swift     # Full release detail
│   ├── Detail/
│   │   ├── TracksTab.swift             # Tracklist + Apple Music player
│   │   ├── CreditsTab.swift
│   │   └── NotesTab.swift              # Editable personal notes/rating
│   ├── Search/
│   │   ├── SearchBar.swift
│   │   └── AdvancedSearchView.swift    # Field-prefix query builder
│   ├── Tools/
│   │   ├── ToolsView.swift             # Sync controls with progress
│   │   └── SyncProgressView.swift
│   ├── Statistics/
│   │   └── StatisticsView.swift        # Charts by artist, genre, decade, format
│   └── Settings/
│       └── SettingsView.swift          # Discogs token, Apple Music token
└── Extensions/
    └── Color+Theme.swift
```

---

## Navigation Structure

`NavigationSplitView` with three columns:

**Sidebar**
- My Collection
- Wantlist
- Statistics
- Randomizer
- Tools (sync)
- Smart Collections (saved searches, user-created)
- Settings

**Main content** — grid or list of releases (toggle between views)

**Detail panel** — release detail with tabbed layout: Overview / Tracks / Credits / Notes

---

## Features Checklist

### Sync & Data
- [ ] Initial sync (collection + wantlist) with real-time progress
- [ ] Incremental refresh
- [ ] Full release enrichment (tracklist, credits, identifiers)
- [ ] Push local edits (rating, condition, notes) back to Discogs
- [ ] Header-aware rate limiting + retries on Discogs API calls
- [ ] iCloud sync via CloudKit (automatic, background)

### Browsing
- [ ] Grid view (album art focus) and list view (dense metadata)
- [ ] Sort by: Date Added, Year, Artist, Title, Rating
- [ ] Full-text search (NSPredicate across artist, title, label, notes, tracklist)
- [ ] Advanced search with field prefixes (artist:, genre:, year:, etc.)
- [ ] Year range syntax (e.g. `year:1977..1982`)
- [ ] Smart Collections (saved searches, sidebar shortcuts)

### Release Detail
- [ ] Overview tab: art, metadata, identifiers
- [ ] Tracks tab: tracklist + Apple Music player (barcode match)
- [ ] Credits tab: musicians, companies
- [ ] Notes tab: editable personal notes, rating, media/sleeve condition

### Discovery
- [ ] Live Discogs search (search Discogs directly, not local DB)
- [ ] Add release to collection or wantlist from search results
- [ ] Randomizer ("Surprise Me" button)

### Statistics
- [ ] Charts: by artist, genre, decade, format (using Swift Charts)

### Images
- [ ] Download and cache cover art locally
- [ ] 1 req/sec throttle, 1000/day cap (tracked in SyncState)
- [ ] Fallback to Discogs URL if local image not yet cached

### Apple Music
- [ ] Match release by barcode to Apple Music catalog
- [ ] Embed MusicKit player on Tracks tab
- [ ] Cache matches locally

### Export
- [ ] Static site export (HTML snapshot of collection) — lower priority, do last

---

## Discogs API Notes

- Base URL: `https://api.discogs.com`
- Auth: `Authorization: Discogs token=YOUR_TOKEN` header
- Rate limit headers to respect: `X-Discogs-Ratelimit`, `X-Discogs-Ratelimit-Used`, `X-Discogs-Ratelimit-Remaining`
- Retry on 429 with backoff
- User-Agent header required: `MyMusicCollection/1.0 +yourcontact`
- Image downloads: separate 1 req/sec throttle, separate 1000/day cap

---

## iCloud Sync Notes

- Use `NSPersistentCloudKitContainer` instead of `NSPersistentContainer`
- Enable CloudKit capability in Xcode, create a CloudKit container
- `automaticallyMergesChangesFromParent = true` on main context
- CloudKit syncs Core Data changes automatically in background
- Local image cache (disk files) does NOT sync via CloudKit — each device downloads its own images. This is correct behavior; image files are too large and can be re-fetched.
- SyncState (last refresh date, image caps) should also NOT sync — it's device-local. Use UserDefaults instead of Core Data for sync state.

---

## Settings (stored in Keychain)

- Discogs username
- Discogs personal access token
- Apple Music Developer Token (JWT)

---

## Build Order

1. Core Data schema + PersistenceController with CloudKit
2. DiscogsClient (networking, rate limiting, retries)
3. SyncService — initial sync only
4. Basic CollectionView (list, no images yet)
5. ImageCacheService
6. ReleaseDetailView (overview tab)
7. Search (basic, then advanced)
8. Smart Collections
9. Enrich sync + Credits/Tracks tabs
10. Apple Music integration
11. Statistics view (Swift Charts)
12. Push sync (notes/ratings back to Discogs)
13. Randomizer
14. Live Discogs search
15. Tools/sync UI with progress
16. Settings view
17. Static export (if desired)

---

## Instructions for Claude Code

Feed it this document and say:

> *"Build this macOS SwiftUI app from scratch following this design document. Start with step 1 of the build order and work through each step sequentially. Ask me before moving to the next major step."*

The sequential approach matters — Core Data schema changes get painful after you've built views on top of them, so locking that in first saves a lot of rework.

Also commit as often as makes sense for a good log of the development process
