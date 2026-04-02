# Vinyl Crate

A native macOS app for managing your vinyl (and other format) record collection, powered by the Discogs API with Apple Music integration.

## Features

- **Discogs Sync** — Import your full collection and wantlist from Discogs, with incremental refresh
- **Enrichment** — Fetch detailed metadata including tracklists, credits, identifiers, and additional artwork
- **Apple Music Integration** — Match releases to Apple Music and play tracks directly in the app
- **Search** — Filter your collection by artist name
- **Smart Collections** — Save search queries as dynamic collections with live counts
- **Statistics** — Charts for genres, decades, formats, and top artists (Swift Charts)
- **Randomizer** — "Surprise Me" button to pick a random album from your collection
- **Discogs Search** — Search the Discogs database and add releases to your collection or wantlist
- **Push to Discogs** — Sync ratings, conditions, and personal notes back to your Discogs account
- **Artwork Backfill** — Download all additional artwork (back covers, inserts, etc.) with a 1000/day cap
- **iCloud Sync** — Core Data + CloudKit for automatic sync across your Macs
- **Image Caching** — Disk + memory cache with rate limiting for Discogs image downloads

## Requirements

- macOS 15.0+
- Xcode 16+
- A [Discogs](https://www.discogs.com) account with a [personal access token](https://www.discogs.com/settings/developers)
- Apple Music subscription (optional, for playback features)

## Setup

1. Clone the repository
2. Open `wax_log.xcodeproj` in Xcode
3. In Signing & Capabilities:
   - Set your development team
   - Ensure **CloudKit** is enabled with container `iCloud.waxlog`
   - Enable **MusicKit** on your App ID at [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list)
4. Build and run
5. Go to **Settings** in the sidebar, enter your Discogs username and personal access token
6. Go to **Tools** and click **Sync Now** to import your collection

## Architecture

- **SwiftUI** with `NavigationSplitView` (sidebar / content / detail)
- **Core Data** with `NSPersistentCloudKitContainer` for local-first storage + iCloud sync
- **Swift Concurrency** — actors for thread-safe networking and image caching
- **MusicKit** for Apple Music catalog search and playback
- **Swift Charts** for the statistics dashboard

### Project Structure

```
wax_log/
├── Models/
│   └── Release+Extensions.swift
├── Persistence/
│   └── PersistenceController.swift
├── Services/
│   ├── AppleMusicService.swift
│   ├── DiscogsClient.swift
│   ├── ImageCacheService.swift
│   ├── KeychainService.swift
│   ├── SearchService.swift
│   └── SyncService.swift
├── Views/
│   ├── Collection/          # List, grid, cards, detail, randomizer
│   ├── Detail/              # Tracks, credits, artwork, notes tabs
│   ├── Search/              # Discogs search, advanced search
│   ├── Settings/            # Credentials & preferences
│   ├── Sidebar/             # Smart collection management
│   ├── Statistics/          # Charts dashboard
│   └── Tools/               # Sync controls & cache management
├── WaxLog.xcdatamodeld      # Core Data schema
├── ContentView.swift         # Main navigation
└── wax_logApp.swift          # App entry point
```

## Discogs API Usage

This app respects Discogs API guidelines:
- 1 request/second rate limiting
- Exponential backoff on 429 responses
- 1000 image downloads per day cap
- Proper `User-Agent` header identification

## License

MIT
