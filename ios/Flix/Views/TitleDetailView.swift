import SwiftData
import SwiftUI

/// Netflix-style title page: artwork pinned at the top, Play, actions, and
/// Episodes / More Like This tabs.
struct TitleDetailView: View {
    let title: Title
    /// The first page in the cover closes it; pushed pages go back.
    var isRoot = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var ratings: RatingStore
    @AppStorage(Keys.tmdbKey) private var tmdbKey = ""
    @Query private var items: [LibraryItem]
    @Query private var progress: [WatchProgress]

    private enum Tab: Hashable { case episodes, more }

    @State private var detail: Title?
    @State private var certification: String?
    @State private var lengthLabel: String?
    @State private var castLine: String?
    @State private var creatorLine: String?
    @State private var similar: [Title] = []
    @State private var seasons: [SeasonSummary] = []
    @State private var season = 1
    @State private var episodes: [Episode] = []
    @State private var loadingEpisodes = false
    @State private var episodesFailed = false
    /// Which season `episodes` belongs to, so a switch never shows the old list.
    @State private var episodesSeason: Int?
    @State private var detailError: String?
    @State private var runtime: Int?
    @State private var tab: Tab = .episodes
    @State private var visit: SiteVisit?
    @State private var showRating = false
    @State private var appeared = false
    @Namespace private var tabLine

    init(title: Title, isRoot: Bool = true) {
        self.title = title
        self.isRoot = isRoot
        let key = title.key
        _items = Query(filter: #Predicate<LibraryItem> { $0.key == key })
        _progress = Query(filter: #Predicate<WatchProgress> { $0.titleKey == key })
        _tab = State(initialValue: title.type == .tv ? .episodes : .more)
    }

    private var shown: Title { detail ?? title }
    private var item: LibraryItem? { items.first }
    private var inList: Bool { item?.inWatchlist == true }
    private var rating: Int { ratings.rating(for: title.key) }
    private var progressByKey: [String: WatchProgress] {
        Dictionary(progress.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ScrollView {
            // The artwork scrolls away with the page. (A pinned header let the
            // text slide up over it and under the clock.)
            LazyVStack(alignment: .leading, spacing: 0) {
                artwork
                info
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        // A solid strip behind the status bar, so scrolled text never runs under the clock.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0).background(Color.black.ignoresSafeArea(edges: .top))
        }
        // Close/back stays reachable after the artwork scrolls off: the
        // navigation bar is hidden and a full-screen cover can't be swiped away.
        .overlay(alignment: .topTrailing) { closeButton }
        .background(Theme.card.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadDetail() }
        .task(id: season) { await loadSeason() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.12)) { appeared = true }
        }
        .playerCover($visit)
    }

    // MARK: Artwork

    private var artwork: some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay { PosterImage(path: shown.backdropPath ?? shown.posterPath, name: shown.name, size: "w1280") }
            .overlay {
                Button {
                    play(nextRequest)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(.black.opacity(0.45), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                }
                .buttonStyle(PressableStyle(scale: 0.88))
                .accessibilityLabel("Play \(shown.name)")
            }
            .overlay(alignment: .bottom) {
                if let saved = resumeProgress {
                    ProgressBar(fraction: saved.fraction)
                }
            }
            .clipped()
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: isRoot ? "xmark" : "chevron.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .padding(5)
        .accessibilityLabel(isRoot ? "Close" : "Back")
    }

    // MARK: Info

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(shown.name)
                .font(.system(size: 22, weight: .bold))
                .padding(.bottom, 6)
            metaRow
            if let rank = HomeModel.todayRanks[title.key] {
                HStack(spacing: 8) {
                    Top10Badge(scale: 1.05)
                    Text("#\(rank) in \(title.type == .tv ? "Shows" : "Movies") Today").font(.system(size: 15, weight: .bold))
                }
                .padding(.top, 10)
            }
            playButton.padding(.top, 14)
            if let saved = resumeProgress {
                HStack(spacing: 10) {
                    ProgressBar(fraction: saved.fraction).clipShape(Capsule())
                    Text(Format.remaining(saved.duration - saved.position))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(white: 0.67))
                }
                .padding(.top, 10)
            }
            if let detailError {
                HStack(spacing: 10) {
                    Text(detailError).foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadDetail() } }
                }
                .font(.subheadline)
                .padding(.top, 12)
            }
            synopsis.padding(.top, 14)
            actions.padding(.top, 18)
            tabs.padding(.top, 10)
            tabContent
        }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if rating >= 2 {
                Image(systemName: rating == 3 ? "hand.thumbsup.circle.fill" : "hand.thumbsup.fill")
                    .font(.system(size: 14))
            }
            if let year = shown.year { Text(year) }
            if let certification { RatingBadge(text: certification) }
            if let lengthLabel { Text(lengthLabel) }
            Image(systemName: "captions.bubble").font(.system(size: 14))
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color(white: 0.74))
    }

    private var playButton: some View {
        let next = nextRequest
        let resuming = resumeProgress != nil
        return FilledButton(title: playLabel(next, resuming: resuming), systemImage: "play.fill") {
            play(next)
        }
    }

    @ViewBuilder
    private var synopsis: some View {
        VStack(alignment: .leading, spacing: 6) {
            if title.type == .tv, let ep = currentEpisode {
                Text("S\(ep.seasonNumber):E\(ep.episodeNumber) \(ep.name ?? "")")
                    .font(.system(size: 15, weight: .bold))
                Text(ep.overview?.isEmpty == false ? ep.overview! : shown.overview)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color(white: 0.92))
            } else if !shown.overview.isEmpty {
                Text(shown.overview)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color(white: 0.92))
            }
            if let castLine {
                Text(castLine).font(.system(size: 12.5)).foregroundStyle(Color(white: 0.6)).lineLimit(2)
            }
            if let creatorLine {
                Text(creatorLine).font(.system(size: 12.5)).foregroundStyle(Color(white: 0.6)).lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack(alignment: .top, spacing: 0) {
            action(inList ? "checkmark" : "plus", "My List") { toggleWatchlist() }
            action(ratingIcon, rating == 0 ? "Rate" : "Rated") { showRating = true }
                .popover(isPresented: $showRating, arrowEdge: .bottom) {
                    RatePicker(current: rating) { value in
                        ratings.toggle(value, for: title.key)
                        _ = Library.item(for: shown, in: context)
                        showRating = false
                    }
                    .presentationCompactAdaptation(.popover)
                }
            ShareLink(item: shareURL, subject: Text(shown.name)) {
                actionLabel("paperplane", "Share")
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .frame(maxWidth: .infinity)
            if title.type == .movie {
                let movie = PlayRequest(title: shown)
                let done = progressByKey[movie.progressKey]?.isFinished == true
                action(done ? "checkmark.circle.fill" : "checkmark.circle", done ? "Watched" : "Mark Watched") {
                    Library.setWatched(movie, !done, runtimeMinutes: runtime, in: context)
                }
            }
        }
    }

    private var ratingIcon: String {
        switch rating {
        case 1: return "hand.thumbsdown.fill"
        case 2: return "hand.thumbsup.fill"
        case 3: return "hand.thumbsup.circle.fill"
        default: return "hand.thumbsup"
        }
    }

    private func action(_ icon: String, _ label: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            actionLabel(icon, label)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .frame(maxWidth: .infinity)
    }

    private func actionLabel(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .frame(height: 28)
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.74))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 22) {
            if title.type == .tv { tabButton(.episodes, "Episodes") }
            tabButton(.more, "More Like This")
            Spacer()
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color(white: 0.17)).frame(height: 1)
        }
    }

    private func tabButton(_ t: Tab, _ label: String) -> some View {
        Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) { tab = t }
        } label: {
            Text(label)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tab == t ? .white : Color(white: 0.55))
                .padding(.top, 14)
                .padding(.bottom, 10)
                .overlay(alignment: .top) {
                    if tab == t {
                        Rectangle().fill(Theme.accent).frame(height: 4)
                            .matchedGeometryEffect(id: "line", in: tabLine)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            if tab == .episodes && title.type == .tv {
                episodesSection
            } else {
                moreLikeThis
            }
        }
        .transition(.opacity)
        .id(tab)
    }

    @ViewBuilder
    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !seasons.isEmpty {
                HStack {
                    seasonMenu
                    Spacer()
                    seasonOptions
                }
                .padding(.vertical, 8)
            }
            if loadingEpisodes && (episodes.isEmpty || episodesStale) {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if episodesFailed {
                HStack {
                    Text("Couldn't load episodes.").foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadSeason() } }
                }
                .font(.subheadline)
                .padding(.vertical, 12)
            }
            episodeList
                // The previous season stays (dimmed, not tappable) until the
                // new one arrives, so the page keeps its height and scroll spot.
                .opacity(episodesStale ? 0.3 : 1)
                .allowsHitTesting(!episodesStale)
                .accessibilityHidden(episodesStale)
        }
        .animation(.easeOut(duration: 0.25), value: episodes)
    }

    /// `episodes` still holds another season's list while a new one loads.
    private var episodesStale: Bool { episodesSeason != nil && episodesSeason != season }

    private var episodeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(episodes) { ep in
                let request = PlayRequest(title: shown, season: ep.seasonNumber, episode: ep.episodeNumber)
                EpisodeRow(episode: ep, progress: progressByKey[request.progressKey]) {
                    play(request)
                }
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
    }

    private func seasonName(_ s: SeasonSummary) -> String {
        s.name ?? "Season \(s.seasonNumber)"
    }

    private var seasonMenu: some View {
        Menu {
            Picker("Season", selection: $season) {
                ForEach(seasons, id: \.seasonNumber) { s in
                    Text(seasonName(s)).tag(s.seasonNumber)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(seasons.first { $0.seasonNumber == season }.map(seasonName) ?? "Season \(season)")
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 5))
        }
        .accessibilityLabel("Season")
    }

    private var seasonOptions: some View {
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
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white)
        }
        .disabled(episodes.isEmpty || episodesStale)
        .accessibilityLabel("Season options")
    }

    @ViewBuilder
    private var moreLikeThis: some View {
        if similar.isEmpty {
            Text(detail == nil ? (detailError == nil ? "" : "Couldn't load suggestions.") : "Nothing similar found.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                ForEach(similar) { t in
                    NavigationLink(value: t) {
                        PosterTile(title: t, rank: HomeModel.todayRanks[t.key], width: nil)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: Actions

    private var resumeProgress: WatchProgress? {
        guard let saved = progressByKey[nextRequest.progressKey], saved.position > 30, !saved.isFinished else { return nil }
        return saved
    }

    private var currentEpisode: Episode? {
        let next = nextRequest
        return episodes.first { $0.seasonNumber == next.season && $0.episodeNumber == next.episode }
    }

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
        guard let s = request.season, let e = request.episode, item?.lastSeason != nil else { return verb }
        return "\(verb) S\(s):E\(e)"
    }

    private var shareURL: URL {
        URL(string: "https://www.themoviedb.org/\(title.type.rawValue)/\(title.tmdbID)")!
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
        withAnimation(.spring(duration: 0.35, bounce: 0.4)) {
            entry.inWatchlist.toggle()
            entry.watchlistAddedAt = .now
        }
    }

    // MARK: Loading

    private func loadDetail() async {
        guard detail == nil, let client = TMDB.client(userKey: tmdbKey) else { return }
        detailError = nil
        do {
            switch title.type {
            case .movie:
                let m = try await client.movieFull(title.tmdbID)
                var t = title
                t.name = m.title
                t.overview = m.overview ?? title.overview
                t.posterPath = m.posterPath ?? title.posterPath
                t.backdropPath = m.backdropPath ?? title.backdropPath
                if let date = m.releaseDate, date.count >= 4 { t.year = String(date.prefix(4)) }
                t.genreIDs = m.genres?.map(\.id) ?? title.genreIDs
                runtime = m.runtime
                lengthLabel = m.runtime.flatMap { $0 > 0 ? "\($0 / 60)h \($0 % 60)m" : nil }
                certification = m.certification
                castLine = Self.castLine(m.credits)
                let directors = (m.credits?.crew ?? []).filter { $0.job == "Director" }.map(\.name)
                creatorLine = directors.isEmpty ? nil : "Director: " + directors.prefix(2).joined(separator: ", ")
                similar = m.recommendations?.titles(defaultType: .movie) ?? []
                withAnimation(.easeOut(duration: 0.25)) { detail = t }
            case .tv:
                let s = try await client.showFull(title.tmdbID)
                var t = title
                t.name = s.name
                t.overview = s.overview ?? title.overview
                t.posterPath = s.posterPath ?? title.posterPath
                t.backdropPath = s.backdropPath ?? title.backdropPath
                if let date = s.firstAirDate, date.count >= 4 { t.year = String(date.prefix(4)) }
                t.genreIDs = s.genres?.map(\.id) ?? title.genreIDs
                let all = s.seasons ?? []
                let regular = all.filter { $0.seasonNumber > 0 }
                seasons = regular.isEmpty ? all : regular
                if let last = item?.lastSeason, seasons.contains(where: { $0.seasonNumber == last }) {
                    season = last
                } else if let first = seasons.first {
                    season = first.seasonNumber
                }
                lengthLabel = s.numberOfSeasons.map { $0 == 1 ? "1 Season" : "\($0) Seasons" }
                certification = s.certification
                castLine = Self.castLine(s.credits)
                let creators = (s.createdBy ?? []).map(\.name)
                creatorLine = creators.isEmpty ? nil : "Creators: " + creators.prefix(3).joined(separator: ", ")
                similar = s.recommendations?.titles(defaultType: .tv) ?? []
                withAnimation(.easeOut(duration: 0.25)) { detail = t }
            }
            // Keep saved copies' posters and text fresh.
            if let item, let detail { item.update(from: detail) }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            detailError = error.localizedDescription
        }
        // The season task already ran (with no seasons yet), and won't run
        // again if the season picked above is the default one.
        if title.type == .tv { await loadSeason() }
    }

    private static func castLine(_ credits: Credits?) -> String? {
        let names = (credits?.cast ?? []).prefix(4).map(\.name)
        return names.isEmpty ? nil : "Cast: " + names.joined(separator: ", ")
    }

    private func loadSeason() async {
        guard title.type == .tv, !seasons.isEmpty, let client = TMDB.client(userKey: tmdbKey) else { return }
        let number = season
        loadingEpisodes = true
        episodesFailed = false
        // A cancelled load for a season no longer picked mustn't hide the
        // spinner of the one that replaced it.
        defer { if season == number { loadingEpisodes = false } }
        do {
            let loaded = try await client.season(title.tmdbID, number).episodes
            // A slower load for a season no longer picked mustn't win.
            if season == number {
                episodes = loaded
                episodesSeason = number
            }
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            guard season == number else { return }
            if episodesSeason != number {
                // Don't leave another season's list under this one's name.
                episodes = []
                episodesSeason = nil
            }
            if episodes.isEmpty { episodesFailed = true }
        }
    }
}

/// Not for me / I like this / Love this, in a glass bubble.
struct RatePicker: View {
    let current: Int
    let pick: (Int) -> Void
    @State private var shown = false

    var body: some View {
        HStack(spacing: 6) {
            option(1, "hand.thumbsdown", "Not for me")
            option(2, "hand.thumbsup", "I like this")
            option(3, "hand.thumbsup.circle", "Love this!")
        }
        .padding(10)
        .onAppear { shown = true }
    }

    private func option(_ value: Int, _ icon: String, _ label: String) -> some View {
        Button {
            pick(value)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: current == value ? icon + ".fill" : icon)
                    .font(.system(size: 24))
                    .symbolEffect(.bounce, value: current == value)
                Text(label).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 70, height: 62)
            .background(current == value ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .scaleEffect(shown ? 1 : 0.4)
            .opacity(shown ? 1 : 0)
            .animation(.spring(duration: 0.4, bounce: 0.45).delay(Double(value) * 0.05), value: shown)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let progress: WatchProgress?
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    Color.clear
                        .frame(width: 126, height: 71)
                        .overlay { PosterImage(path: episode.stillPath, name: "E\(episode.episodeNumber)", size: "w300") }
                        .overlay {
                            Image(systemName: progress?.isFinished == true ? "checkmark" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(.black.opacity(0.5), in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 1.2))
                        }
                        .overlay(alignment: .bottom) {
                            if let progress, progress.fraction > 0 {
                                ProgressBar(fraction: progress.fraction)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(episode.episodeNumber). \(episode.name ?? "Episode \(episode.episodeNumber)")")
                            .font(.system(size: 14.5, weight: .medium))
                            .lineLimit(2)
                        if let runtime = episode.runtime, runtime > 0 {
                            Text("\(runtime)m").font(.system(size: 12.5)).foregroundStyle(Color(white: 0.6))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .accessibilityLabel("Episode \(episode.episodeNumber), \(episode.name ?? "")")
            .accessibilityValue(progress?.isFinished == true ? "Watched"
                                : (progress.map { $0.fraction > 0 } == true ? "In progress" : ""))
            .accessibilityHint("Plays the episode")
            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color(white: 0.71))
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 10)
    }
}
