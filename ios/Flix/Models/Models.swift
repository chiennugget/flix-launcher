import Foundation
import SwiftData

enum MediaType: String, Codable, Hashable {
    case movie, tv
}

/// A movie or show as shown in rows and detail pages (from TMDB or the library).
struct Title: Identifiable, Hashable, Codable {
    let tmdbID: Int
    let type: MediaType
    var name: String
    var overview: String = ""
    var posterPath: String?
    var backdropPath: String?
    var year: String?
    var rating: Double?

    var key: String { "\(type.rawValue):\(tmdbID)" }
    var id: String { key }
}

/// One thing to play: a movie, or one episode of a show.
struct PlayRequest: Hashable {
    let title: Title
    var season: Int?
    var episode: Int?

    var progressKey: String {
        guard let season, let episode else { return title.key }
        return "\(title.key):s\(season)e\(episode)"
    }

    var episodeLabel: String? {
        guard let season, let episode else { return nil }
        return "S\(season) E\(episode)"
    }

    var displayName: String {
        [title.name, episodeLabel].compactMap { $0 }.joined(separator: " · ")
    }

    /// The episode after this one, or nil at the end of the show (or when the
    /// seasons aren't known).
    func next(in seasons: [SeasonSummary]) -> PlayRequest? {
        guard let season, let episode else { return nil }
        let count = seasons.first { $0.seasonNumber == season }?.episodeCount ?? 0
        if episode < count { return PlayRequest(title: title, season: season, episode: episode + 1) }
        if seasons.contains(where: { $0.seasonNumber == season + 1 }) {
            return PlayRequest(title: title, season: season + 1, episode: 1)
        }
        return nil
    }

    /// Values for the {placeholders} in domain.json's link templates.
    var variables: [String: String] {
        let slug = title.name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        return [
            "id": String(title.tmdbID),
            "type": title.type.rawValue,
            "title": title.name,
            "query": title.name,
            "slug": slug,
            "year": title.year ?? "",
            "season": String(season ?? 1),
            "episode": String(episode ?? 1),
        ]
    }
}

/// A title the user has saved or watched. Holds My List and history.
@Model
final class LibraryItem {
    @Attribute(.unique) var key: String
    var tmdbID: Int
    var typeRaw: String
    var name: String
    var overview: String
    var posterPath: String?
    var backdropPath: String?
    var year: String?
    var rating: Double?

    var inWatchlist: Bool
    var watchlistAddedAt: Date
    var inHistory: Bool
    var lastWatchedAt: Date
    var lastSeason: Int?
    var lastEpisode: Int?
    var resumeLabel: String?
    var resumeFraction: Double

    init(_ title: Title) {
        key = title.key
        tmdbID = title.tmdbID
        typeRaw = title.type.rawValue
        name = title.name
        overview = title.overview
        posterPath = title.posterPath
        backdropPath = title.backdropPath
        year = title.year
        rating = title.rating
        inWatchlist = false
        watchlistAddedAt = .distantPast
        inHistory = false
        lastWatchedAt = .distantPast
        resumeFraction = 0
    }

    var asTitle: Title {
        Title(tmdbID: tmdbID, type: MediaType(rawValue: typeRaw) ?? .movie, name: name,
              overview: overview, posterPath: posterPath, backdropPath: backdropPath,
              year: year, rating: rating)
    }

    func update(from title: Title) {
        name = title.name
        if !title.overview.isEmpty { overview = title.overview }
        posterPath = title.posterPath ?? posterPath
        backdropPath = title.backdropPath ?? backdropPath
        year = title.year ?? year
        rating = title.rating ?? rating
    }
}

/// Playback position for one movie or episode, plus the site link it played from.
@Model
final class WatchProgress {
    @Attribute(.unique) var key: String
    var titleKey: String
    var season: Int?
    var episode: Int?
    var position: Double
    var duration: Double
    var updatedAt: Date
    /// Path on the site where this played, learned while watching. Kept
    /// relative so it survives domain changes.
    var sitePath: String?

    init(key: String, titleKey: String, season: Int?, episode: Int?) {
        self.key = key
        self.titleKey = titleKey
        self.season = season
        self.episode = episode
        position = 0
        duration = 0
        updatedAt = .now
    }

    var fraction: Double { duration > 0 ? min(position / duration, 1) : 0 }
    var isFinished: Bool { fraction >= 0.95 }
}

@MainActor
enum Library {
    static func item(for title: Title, in context: ModelContext) -> LibraryItem {
        let key = title.key
        var descriptor = FetchDescriptor<LibraryItem>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.update(from: title)
            return existing
        }
        let item = LibraryItem(title)
        context.insert(item)
        return item
    }

    static func existingProgress(key: String, in context: ModelContext) -> WatchProgress? {
        var descriptor = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func progress(for request: PlayRequest, in context: ModelContext) -> WatchProgress {
        if let existing = existingProgress(key: request.progressKey, in: context) { return existing }
        let progress = WatchProgress(key: request.progressKey, titleKey: request.title.key,
                                     season: request.season, episode: request.episode)
        context.insert(progress)
        return progress
    }

    /// Marks a movie or episode watched (or not) without playing it.
    /// `updateHistory: false` skips Continue Watching, for marking a batch.
    static func setWatched(_ request: PlayRequest, _ watched: Bool, runtimeMinutes: Int? = nil,
                           updateHistory: Bool = true, in context: ModelContext) {
        let progress = Self.progress(for: request, in: context)
        if watched {
            if progress.duration <= 0 { progress.duration = Double(max(runtimeMinutes ?? 0, 1) * 60) }
            progress.position = progress.duration
        } else {
            progress.position = 0
        }
        progress.updatedAt = .now
        guard updateHistory else { return }
        let item = Self.item(for: request.title, in: context)
        let isLast = item.lastSeason == request.season && item.lastEpisode == request.episode
        // Watched: Play moves on to the next episode. Unwatched: only refresh
        // the Continue Watching label if this was the one it pointed at.
        if watched || (item.inHistory && isLast) {
            markWatched(request, progress: progress, in: context)
        }
    }

    /// Records that a request was opened or played, for Continue Watching.
    static func markWatched(_ request: PlayRequest, progress: WatchProgress?, in context: ModelContext) {
        let item = Self.item(for: request.title, in: context)
        item.inHistory = true
        item.lastWatchedAt = .now
        item.lastSeason = request.season
        item.lastEpisode = request.episode
        guard let progress, progress.duration > 0 else {
            item.resumeLabel = request.episodeLabel
            item.resumeFraction = 0
            return
        }
        let left = progress.isFinished ? "Watched" : Format.remaining(progress.duration - progress.position)
        item.resumeLabel = [request.episodeLabel, left].compactMap { $0 }.joined(separator: " · ")
        item.resumeFraction = progress.fraction
    }
}
