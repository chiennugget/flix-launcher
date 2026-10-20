import SwiftData
import SwiftUI

struct TitleDetailView: View {
    let title: Title

    @Environment(\.modelContext) private var context
    @AppStorage(Keys.tmdbKey) private var tmdbKey = ""
    @Query private var items: [LibraryItem]
    @Query private var progress: [WatchProgress]

    @State private var detail: Title?
    @State private var meta: [String] = []
    @State private var tagline: String?
    @State private var seasons: [SeasonSummary] = []
    @State private var season = 1
    @State private var episodes: [Episode] = []
    @State private var loadingEpisodes = false
    @State private var episodesFailed = false
    @State private var runtime: Int?
    @State private var visit: SiteVisit?

    init(title: Title) {
        self.title = title
        let key = title.key
        _items = Query(filter: #Predicate<LibraryItem> { $0.key == key })
        _progress = Query(filter: #Predicate<WatchProgress> { $0.titleKey == key })
    }

    private var shown: Title { detail ?? title }
    private var item: LibraryItem? { items.first }
    private var progressByKey: [String: WatchProgress] {
        Dictionary(progress.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                VStack(alignment: .leading, spacing: 14) {
                    Text(shown.name).font(.largeTitle.bold())
                    if !meta.isEmpty {
                        Text(meta.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    actions
                    if let tagline, !tagline.isEmpty {
                        Text(tagline).font(.callout.italic()).foregroundStyle(.secondary)
                    }
                    if !shown.overview.isEmpty {
                        Text(shown.overview).font(.body)
                    }
                    if title.type == .tv { episodesSection }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
        .task(id: season) { await loadSeason() }
        .fullScreenCover(item: $visit) { PlayerScreen(visit: $0) }
    }

    // MARK: Sections

    private var header: some View {
        Color.clear
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay { PosterImage(path: shown.backdropPath ?? shown.posterPath, name: shown.name, size: "w1280") }
            .overlay {
                LinearGradient(colors: [.clear, Color(uiColor: .systemBackground)], startPoint: .center, endPoint: .bottom)
            }
            .clipped()
    }

    private var actions: some View {
        let next = nextRequest
        let saved = progressByKey[next.progressKey]
        let resuming = saved.map { $0.position > 30 && !$0.isFinished } ?? false
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                play(next)
            } label: {
                Label(playLabel(next, resuming: resuming), systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)

            if resuming, let saved {
                ProgressBar(fraction: saved.fraction)
                Text(Format.remaining(saved.duration - saved.position)).font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    toggleWatchlist()
                } label: {
                    Label(item?.inWatchlist == true ? "In My List" : "My List",
                          systemImage: item?.inWatchlist == true ? "checkmark" : "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                if title.type == .movie {
                    let movie = PlayRequest(title: shown)
                    let done = progressByKey[movie.progressKey]?.isFinished == true
                    Button {
                        Library.setWatched(movie, !done, runtimeMinutes: runtime, in: context)
                    } label: {
                        Label(done ? "Watched" : "Mark Watched",
                              systemImage: done ? "checkmark.circle.fill" : "checkmark.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    @ViewBuilder
    private var episodesSection: some View {
        if !seasons.isEmpty {
            HStack {
                Text("Episodes").font(.title2.bold())
                Spacer()
                Picker("Season", selection: $season) {
                    ForEach(seasons, id: \.seasonNumber) { s in
                        Text(s.name ?? "Season \(s.seasonNumber)").tag(s.seasonNumber)
                    }
                }
                .pickerStyle(.menu)
                Menu {
                    Button {
                        markSeason(true)
                    } label: {
                        Label("Mark season as watched", systemImage: "checkmark.circle")
                    }
                    Button {
                        markSeason(false)
                    } label: {
                        Label("Mark season as unwatched", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .disabled(episodes.isEmpty)
                .accessibilityLabel("Season options")
            }
            .padding(.top, 8)
        }
        if loadingEpisodes && episodes.isEmpty {
            ProgressView().frame(maxWidth: .infinity)
        } else if episodesFailed {
            HStack {
                Text("Couldn't load episodes.").foregroundStyle(.secondary)
                Button("Retry") { Task { await loadSeason() } }
            }
            .font(.subheadline)
        }
        ForEach(episodes) { ep in
            let request = PlayRequest(title: shown, season: ep.seasonNumber, episode: ep.episodeNumber)
            Button {
                play(request)
            } label: {
                EpisodeRow(episode: ep, progress: progressByKey[request.progressKey])
            }
            .buttonStyle(.plain)
            .contextMenu {
                let done = progressByKey[request.progressKey]?.isFinished == true
                Button {
                    play(request)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                Button {
                    Library.setWatched(request, !done, runtimeMinutes: ep.runtime, in: context)
                } label: {
                    Label(done ? "Mark as unwatched" : "Mark as watched",
                          systemImage: done ? "eye.slash" : "checkmark.circle")
                }
            }
        }
    }

    // MARK: Actions

    /// Movie, or the episode to continue: the last one opened, or the one
    /// after it if that was finished.
    private var nextRequest: PlayRequest {
        guard title.type == .tv else { return PlayRequest(title: shown) }
        guard let s = item?.lastSeason, let e = item?.lastEpisode else {
            let first = seasons.first?.seasonNumber ?? 1
            return PlayRequest(title: shown, season: first, episode: 1)
        }
        let last = PlayRequest(title: shown, season: s, episode: e)
        guard progressByKey[last.progressKey]?.isFinished == true else { return last }
        return last.next(in: seasons) ?? last
    }

    private func playLabel(_ request: PlayRequest, resuming: Bool) -> String {
        let verb = resuming ? "Resume" : "Play"
        guard let label = request.episodeLabel else { return verb }
        return "\(verb) \(label)"
    }

    private func play(_ request: PlayRequest) {
        visit = SiteVisit(request: request)
    }

    private func markSeason(_ watched: Bool) {
        let requests = episodes.map { PlayRequest(title: shown, season: $0.seasonNumber, episode: $0.episodeNumber) }
        for (ep, request) in zip(episodes, requests) {
            Library.setWatched(request, watched, runtimeMinutes: ep.runtime, updateHistory: false, in: context)
        }
        // Continue Watching follows the season's last episode, so Play moves on.
        if watched, let last = requests.last {
            Library.markWatched(last, progress: Library.existingProgress(key: last.progressKey, in: context),
                                in: context)
        } else if !watched, let item, item.inHistory, item.lastSeason == season, let first = requests.first {
            Library.markWatched(first, progress: Library.existingProgress(key: first.progressKey, in: context),
                                in: context)
        }
    }

    private func toggleWatchlist() {
        let entry = Library.item(for: shown, in: context)
        entry.inWatchlist.toggle()
        entry.watchlistAddedAt = .now
    }

    // MARK: Loading

    private func loadDetail() async {
        guard detail == nil, let client = TMDB.client(userKey: tmdbKey) else { return }
        do {
            switch title.type {
            case .movie:
                let m = try await client.movie(title.tmdbID)
                var t = title
                t.name = m.title
                t.overview = m.overview ?? title.overview
                t.posterPath = m.posterPath ?? title.posterPath
                t.backdropPath = m.backdropPath ?? title.backdropPath
                detail = t
                tagline = m.tagline
                runtime = m.runtime
                let parts: [String?] = [m.releaseDate.map { String($0.prefix(4)) },
                        m.runtime.flatMap { $0 > 0 ? "\($0 / 60)h \($0 % 60)m" : nil },
                        m.voteAverage.flatMap { $0 > 0 ? String(format: "★ %.1f", $0) : nil },
                        m.genres?.prefix(3).map(\.name).joined(separator: ", ")]
                meta = parts.compactMap { $0 }.filter { !$0.isEmpty }
            case .tv:
                let s = try await client.show(title.tmdbID)
                var t = title
                t.name = s.name
                t.overview = s.overview ?? title.overview
                t.posterPath = s.posterPath ?? title.posterPath
                t.backdropPath = s.backdropPath ?? title.backdropPath
                detail = t
                tagline = s.tagline
                let all = s.seasons ?? []
                let regular = all.filter { $0.seasonNumber > 0 }
                seasons = regular.isEmpty ? all : regular
                if let last = item?.lastSeason, seasons.contains(where: { $0.seasonNumber == last }) {
                    season = last
                } else if let first = seasons.first {
                    season = first.seasonNumber
                }
                let parts: [String?] = [s.firstAirDate.map { String($0.prefix(4)) },
                        s.numberOfSeasons.map { $0 == 1 ? "1 season" : "\($0) seasons" },
                        s.voteAverage.flatMap { $0 > 0 ? String(format: "★ %.1f", $0) : nil },
                        s.genres?.prefix(3).map(\.name).joined(separator: ", ")]
                meta = parts.compactMap { $0 }.filter { !$0.isEmpty }
            }
            // Keep saved copies' posters and text fresh.
            if let item, let detail { item.update(from: detail) }
        } catch {
            meta = [error.localizedDescription]
        }
        // The season task already ran (with no seasons yet), and won't run
        // again if the season picked above is the default one.
        if title.type == .tv { await loadSeason() }
    }

    private func loadSeason() async {
        guard title.type == .tv, !seasons.isEmpty, let client = TMDB.client(userKey: tmdbKey) else { return }
        let number = season
        loadingEpisodes = true
        episodesFailed = false
        defer { loadingEpisodes = false }
        do {
            let loaded = try await client.season(title.tmdbID, number).episodes
            // A slower load for a season no longer picked mustn't win.
            if season == number { episodes = loaded }
        } catch {
            if season == number, episodes.isEmpty { episodesFailed = true }
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let progress: WatchProgress?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear
                .frame(width: 128, height: 72)
                .overlay { PosterImage(path: episode.stillPath, name: "E\(episode.episodeNumber)", size: "w300") }
                .overlay(alignment: .bottom) {
                    if let progress, progress.fraction > 0 {
                        ProgressBar(fraction: progress.fraction).padding(.horizontal, 5).padding(.bottom, 5)
                    }
                }
                .overlay {
                    Image(systemName: progress?.isFinished == true ? "checkmark.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(episode.episodeNumber). \(episode.name ?? "Episode \(episode.episodeNumber)")")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let runtime = episode.runtime, runtime > 0 {
                    Text("\(runtime)m").font(.caption).foregroundStyle(.secondary)
                }
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
