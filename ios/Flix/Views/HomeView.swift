import SwiftData
import SwiftUI

@MainActor
final class HomeModel: ObservableObject {
    enum Filter: Hashable {
        case all, tv, movie
        case category(HomeCategory)
    }

    struct Row: Identifiable {
        let id: String
        let name: String
        let items: [Title]
        let top10: Bool
    }

    private struct Spec {
        let id: String
        let name: String
        let path: String
        var query: [String: String] = [:]
        let type: MediaType?
        var top10 = false
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var hero: Title?
    @Published private(set) var tint = Color(white: 0.16)
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    /// Today's Top 10 positions by title key, for the red corner tags.
    @Published private(set) var ranks: [String: Int] = [:]
    /// Shared with title pages for "#3 in Shows Today".
    static var todayRanks: [String: Int] = [:]
    private var loadedID: String?

    private static func specs(for filter: Filter) -> [Spec] {
        func discover(_ type: MediaType, _ genre: Int, _ extra: [String: String] = [:]) -> [String: String] {
            var q = extra
            q["with_genres"] = String(genre)
            if q["sort_by"] == nil { q["sort_by"] = "popularity.desc" }
            _ = type
            return q
        }
        switch filter {
        case .all:
            return [
                Spec(id: "trending", name: "Trending Now", path: "/trending/all/week", type: nil),
                Spec(id: "top-tv", name: "Top 10 Shows Today", path: "/trending/tv/day", type: .tv, top10: true),
                Spec(id: "popular-tv", name: "Popular Shows", path: "/tv/popular", type: .tv),
                Spec(id: "popular-movies", name: "Popular Movies", path: "/movie/popular", type: .movie),
                Spec(id: "top-movies", name: "Top 10 Movies Today", path: "/trending/movie/day", type: .movie, top10: true),
                Spec(id: "acclaimed-tv", name: "Critically Acclaimed Shows", path: "/tv/top_rated", type: .tv),
                Spec(id: "action", name: "Action", path: "/discover/movie", query: discover(.movie, 28), type: .movie),
                Spec(id: "comedy", name: "Comedy", path: "/discover/movie", query: discover(.movie, 35), type: .movie),
                Spec(id: "crime-tv", name: "Crime TV Thrillers & Mysteries", path: "/discover/tv", query: discover(.tv, 80), type: .tv),
                Spec(id: "horror", name: "Horror", path: "/discover/movie", query: discover(.movie, 27), type: .movie),
                Spec(id: "scifi-tv", name: "Sci-Fi & Fantasy Shows", path: "/discover/tv", query: discover(.tv, 10765), type: .tv),
                Spec(id: "acclaimed-movies", name: "Award-Worthy Movies", path: "/movie/top_rated", type: .movie),
                Spec(id: "animation", name: "Animation", path: "/discover/movie", query: discover(.movie, 16), type: .movie),
            ]
        case .tv:
            return [
                Spec(id: "tv-top", name: "Top 10 Shows Today", path: "/trending/tv/day", type: .tv, top10: true),
                Spec(id: "tv-popular", name: "Popular Shows", path: "/tv/popular", type: .tv),
                Spec(id: "tv-new", name: "New Episodes", path: "/tv/on_the_air", type: .tv),
                Spec(id: "tv-acclaimed", name: "Critically Acclaimed Shows", path: "/tv/top_rated", type: .tv),
                Spec(id: "tv-crime", name: "Crime Shows", path: "/discover/tv", query: discover(.tv, 80), type: .tv),
                Spec(id: "tv-comedy", name: "Comedy Shows", path: "/discover/tv", query: discover(.tv, 35), type: .tv),
                Spec(id: "tv-drama", name: "Drama Shows", path: "/discover/tv", query: discover(.tv, 18), type: .tv),
                Spec(id: "tv-scifi", name: "Sci-Fi & Fantasy Shows", path: "/discover/tv", query: discover(.tv, 10765), type: .tv),
                Spec(id: "tv-reality", name: "Reality TV", path: "/discover/tv", query: discover(.tv, 10764), type: .tv),
                Spec(id: "tv-animation", name: "Animated Shows", path: "/discover/tv", query: discover(.tv, 16), type: .tv),
            ]
        case .movie:
            return [
                Spec(id: "mv-top", name: "Top 10 Movies Today", path: "/trending/movie/day", type: .movie, top10: true),
                Spec(id: "mv-popular", name: "Popular Movies", path: "/movie/popular", type: .movie),
                Spec(id: "mv-new", name: "New Releases", path: "/movie/now_playing", type: .movie),
                Spec(id: "mv-acclaimed", name: "Award-Worthy Movies", path: "/movie/top_rated", type: .movie),
                Spec(id: "mv-action", name: "Action", path: "/discover/movie", query: discover(.movie, 28), type: .movie),
                Spec(id: "mv-comedy", name: "Comedy", path: "/discover/movie", query: discover(.movie, 35), type: .movie),
                Spec(id: "mv-horror", name: "Horror", path: "/discover/movie", query: discover(.movie, 27), type: .movie),
                Spec(id: "mv-thriller", name: "Thrillers", path: "/discover/movie", query: discover(.movie, 53), type: .movie),
                Spec(id: "mv-scifi", name: "Sci-Fi", path: "/discover/movie", query: discover(.movie, 878), type: .movie),
                Spec(id: "mv-romance", name: "Romance", path: "/discover/movie", query: discover(.movie, 10749), type: .movie),
                Spec(id: "mv-animation", name: "Animation", path: "/discover/movie", query: discover(.movie, 16), type: .movie),
            ]
        case .category(let c):
            var specs: [Spec] = []
            if let g = c.tv {
                specs.append(Spec(id: "cat-tv", name: "Popular \(c.name) Shows", path: "/discover/tv",
                                  query: discover(.tv, g), type: .tv))
            }
            if let g = c.movie {
                specs.append(Spec(id: "cat-mv", name: "Popular \(c.name) Movies", path: "/discover/movie",
                                  query: discover(.movie, g), type: .movie))
            }
            if let g = c.tv {
                specs.append(Spec(id: "cat-tv-top", name: "Top Rated \(c.name) Shows", path: "/discover/tv",
                                  query: discover(.tv, g, ["sort_by": "vote_average.desc", "vote_count.gte": "300"]),
                                  type: .tv))
            }
            if let g = c.movie {
                specs.append(Spec(id: "cat-mv-top", name: "Top Rated \(c.name) Movies", path: "/discover/movie",
                                  query: discover(.movie, g, ["sort_by": "vote_average.desc", "vote_count.gte": "500"]),
                                  type: .movie))
                specs.append(Spec(id: "cat-mv-new", name: "New \(c.name) Movies", path: "/discover/movie",
                                  query: discover(.movie, g, ["sort_by": "primary_release_date.desc",
                                                              "vote_count.gte": "40",
                                                              "primary_release_date.lte": Self.today]),
                                  type: .movie))
            }
            return specs
        }
    }

    static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: .now)
    }

    func load(key: String, filter: Filter, force: Bool = false) async {
        guard let client = TMDB.client(userKey: key) else {
            rows = []
            hero = nil
            error = nil
            loadedID = nil
            return
        }
        let id = "\(key)|\(filter)"
        if !force, loadedID == id, !rows.isEmpty { return }
        if loadedID != id {
            rows = []
            hero = nil
        }
        loadedID = id
        error = nil
        loading = true
        defer { if loadedID == id { loading = false } }

        async let rankLoad = Self.loadRanks(client)
        let specs = Self.specs(for: filter)
        var loaded: [(Int, Row)] = []
        var failure: Error?
        await withTaskGroup(of: (Int, Row?, Error?).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask {
                    do {
                        let items = try await client.titles(spec.path, spec.query, type: spec.type)
                        return (index, Row(id: spec.id, name: spec.name, items: items, top10: spec.top10), nil)
                    } catch {
                        return (index, nil, error)
                    }
                }
            }
            for await (index, row, err) in group {
                guard loadedID == id else { continue }
                if let row, !row.items.isEmpty {
                    loaded.append((index, row))
                    loaded.sort { $0.0 < $1.0 }
                    withAnimation(.easeOut(duration: 0.35)) { rows = loaded.map(\.1) }
                    if hero == nil, index == 0 {
                        pickHero()
                    }
                } else if failure == nil {
                    failure = err
                }
            }
        }
        let newRanks = await rankLoad
        guard loadedID == id else { return }
        if !newRanks.isEmpty {
            ranks = newRanks
            Self.todayRanks = newRanks
        }
        if hero == nil { pickHero() }
        if rows.isEmpty, let failure { error = failure.localizedDescription }
        if let color = await ImageTint.color(for: hero?.posterPath) {
            withAnimation(.easeInOut(duration: 0.6)) { tint = color }
        }
    }

    private func pickHero() {
        let candidate = rows.first?.items.first { $0.posterPath != nil && $0.backdropPath != nil }
        guard let candidate else { return }
        withAnimation(.easeOut(duration: 0.4)) { hero = candidate }
    }

    private static func loadRanks(_ client: TMDBClient) async -> [String: Int] {
        async let tv = try? client.titles("/trending/tv/day", type: .tv)
        async let movies = try? client.titles("/trending/movie/day", type: .movie)
        var ranks: [String: Int] = [:]
        for list in [await tv ?? [], await movies ?? []] {
            for (i, t) in list.prefix(10).enumerated() { ranks[t.key] = i + 1 }
        }
        return ranks
    }
}

struct HomeView: View {
    @EnvironmentObject private var site: SiteService
    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var context
    @Environment(\.zoomNamespace) private var zoom
    @AppStorage(Keys.tmdbKey) private var tmdbKey = ""
    @AppStorage(Keys.profileName) private var profileName = "You"
    @StateObject private var model = HomeModel()

    @State private var filter: HomeModel.Filter = .all
    @State private var offset: CGFloat = 0
    @State private var lastOffset: CGFloat = 0
    @State private var pillsHidden = false
    @State private var showCategories = false

    @Query(filter: #Predicate<LibraryItem> { $0.inHistory == true },
           sort: \LibraryItem.lastWatchedAt, order: .reverse)
    private var history: [LibraryItem]

    @Query(filter: #Predicate<LibraryItem> { $0.inWatchlist == true },
           sort: \LibraryItem.watchlistAddedAt, order: .reverse)
    private var watchlist: [LibraryItem]

    private let space = "homeScroll"

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            tintLayer
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollOffsetReader(space: space)
                    Color.clear.frame(height: 100)
                    content
                }
            }
            .coordinateSpace(name: space)
            .scrollIndicators(.hidden)
            .onPreferenceChange(ScrollOffsetKey.self) { scrolled(to: $0) }
            .refreshable {
                await model.load(key: tmdbKey, filter: filter, force: true)
                await site.refresh()
            }
            header
        }
        .overlay {
            if showCategories {
                CategoriesOverlay(selected: selectedCategory) { picked in
                    withAnimation(.easeOut(duration: 0.2)) { showCategories = false }
                    if let picked { setFilter(.category(picked)) } else { setFilter(.all) }
                } onClose: {
                    withAnimation(.easeOut(duration: 0.2)) { showCategories = false }
                }
                .transition(.opacity)
            }
        }
        .task(id: "\(tmdbKey)|\(filter)") { await model.load(key: tmdbKey, filter: filter) }
    }

    // MARK: Layers

    private var tintLayer: some View {
        LinearGradient(colors: [model.tint.opacity(0.95), model.tint.opacity(0.45), .black.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 680)
            .ignoresSafeArea(edges: .top)
            .offset(y: -min(max(offset, 0), 700) * 0.45)
            .opacity(Double(max(0, 1 - offset / 650)))
            .allowsHitTesting(false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(headerTitle)
                    .font(.system(size: 26, weight: .heavy))
                    .contentTransition(.opacity)
                Spacer()
                Button {
                    router.visit = SiteVisit()
                } label: {
                    Image(systemName: "globe").font(.system(size: 21))
                }
                .accessibilityLabel("Open site")
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            pills
                .opacity(pillsHidden ? 0 : 1)
                .offset(y: pillsHidden ? -14 : 0)
                .frame(height: pillsHidden ? 0 : 46, alignment: .top)
                .clipped()
        }
        .background(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.55))
                .ignoresSafeArea(edges: .top)
                .opacity(offset > 6 ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: offset > 6)
        }
    }

    private var pills: some View {
        HStack(spacing: 8) {
            if filter != .all {
                Button {
                    setFilter(.all)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 33, height: 33)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Clear filter")
            }
            if filter == .all || filter == .tv {
                GlassPill(selected: filter == .tv) { setFilter(filter == .tv ? .all : .tv) } label: { Text("Series") }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if filter == .all || filter == .movie {
                GlassPill(selected: filter == .movie) { setFilter(filter == .movie ? .all : .movie) } label: { Text("Films") }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            GlassPill(selected: selectedCategory != nil) {
                withAnimation(.easeOut(duration: 0.22)) { showCategories = true }
            } label: {
                HStack(spacing: 5) {
                    Text(categoryLabel)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if TMDB.client(userKey: tmdbKey) == nil {
            KeyMissingCard().padding(.bottom, 24)
        }
        if let hero = model.hero {
            HeroCard(title: hero, inList: watchlist.contains { $0.key == hero.key }) {
                router.open(hero, from: "hero-\(hero.key)")
            } onPlay: {
                router.play(resumeRequest(for: hero))
            } onList: {
                toggleList(hero)
            }
            .padding(.bottom, 26)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else if model.loading {
            RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.09))
                .aspectRatio(0.72, contentMode: .fit)
                .modifier(Shimmer())
                .padding(.horizontal, 22)
                .padding(.bottom, 26)
        }
        VStack(alignment: .leading, spacing: 24) {
            let resume = continueItems
            if !resume.isEmpty {
                ContinueRow(items: resume, name: "Continue Watching for \(profileName)")
            }
            if filter == .all, !watchlist.isEmpty {
                TitleRow(id: "mylist", name: "My List", titles: watchlist.prefix(20).map(\.asTitle), ranks: model.ranks)
            }
            ForEach(model.rows) { row in
                if row.top10 {
                    Top10Row(id: row.id, name: row.name, titles: row.items)
                } else {
                    TitleRow(id: row.id, name: row.name, titles: row.items, ranks: model.ranks)
                }
            }
            if model.loading && model.rows.isEmpty {
                SkeletonRows()
            }
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
            }
        }
        Color.clear.frame(height: 110)
    }

    // MARK: Helpers

    private var headerTitle: String {
        switch filter {
        case .all: return "Home"
        case .tv: return "Series"
        case .movie: return "Films"
        case .category(let c): return c.name
        }
    }

    private var selectedCategory: HomeCategory? {
        if case .category(let c) = filter { return c }
        return nil
    }

    private var categoryLabel: String {
        if let c = selectedCategory { return c.name }
        return filter == .all ? "Categories" : "All Categories"
    }

    private var continueItems: [LibraryItem] {
        let items = Array(history.prefix(20))
        switch filter {
        case .all: return items
        case .tv: return items.filter { $0.typeRaw == MediaType.tv.rawValue }
        case .movie: return items.filter { $0.typeRaw == MediaType.movie.rawValue }
        case .category: return []
        }
    }

    private func setFilter(_ f: HomeModel.Filter) {
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
            filter = f
            pillsHidden = false
        }
    }

    private func scrolled(to y: CGFloat) {
        let dy = y - lastOffset
        var hide = pillsHidden
        if y < 50 { hide = false } else if dy > 6 { hide = true } else if dy < -8 { hide = false }
        if hide != pillsHidden {
            withAnimation(.easeOut(duration: 0.28)) { pillsHidden = hide }
        }
        offset = y
        lastOffset = y
    }

    private func resumeRequest(for title: Title) -> PlayRequest {
        if let item = history.first(where: { $0.key == title.key }) {
            return PlayRequest(title: title, season: item.lastSeason, episode: item.lastEpisode)
        }
        return title.type == .tv ? PlayRequest(title: title, season: 1, episode: 1) : PlayRequest(title: title)
    }

    private func toggleList(_ title: Title) {
        let item = Library.item(for: title, in: context)
        withAnimation(.spring(duration: 0.35, bounce: 0.4)) {
            item.inWatchlist.toggle()
            item.watchlistAddedAt = .now
        }
    }
}

/// The big poster card at the top of Home.
struct HeroCard: View {
    let title: Title
    let inList: Bool
    let onOpen: () -> Void
    let onPlay: () -> Void
    let onList: () -> Void

    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay { PosterImage(path: title.posterPath, name: title.name, size: "w780") }
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .accessibilityElement()
                .accessibilityLabel(title.name)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the title page")
                .accessibilityAction(perform: onOpen)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(height: 190)
                .allowsHitTesting(false)
            VStack(spacing: 12) {
                tagLine
                HStack(spacing: 10) {
                    FilledButton(title: title.type == .tv ? "Play Series" : "Play", systemImage: "play.fill", action: onPlay)
                    Button(action: onList) {
                        HStack(spacing: 7) {
                            Image(systemName: inList ? "checkmark" : "plus")
                                .font(.system(size: 17, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                            Text("My List")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(PressableStyle(scale: 0.96))
                }
            }
            .padding(16)
        }
        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
        .zoomSource("hero-\(title.key)", in: zoom)
        .shadow(color: .black.opacity(0.55), radius: 25, y: 18)
        .padding(.horizontal, 22)
    }

    private var tagLine: some View {
        let tags = [title.type == .tv ? "Series" : "Film"] + Genres.tags(title.genreIDs)
        return HStack(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { i, tag in
                if i > 0 { Text("•").foregroundStyle(Color(white: 0.55)) }
                Text(tag).fontWeight(i == 0 ? .bold : .medium)
            }
        }
        .font(.system(size: 13.5))
        .foregroundStyle(Color(white: 0.92))
        .lineLimit(1)
    }
}

/// Full-screen list of categories over a blur, with a round close button.
struct CategoriesOverlay: View {
    let selected: HomeCategory?
    let onPick: (HomeCategory?) -> Void
    let onClose: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.6)).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 4) {
                    item("Home", on: selected == nil, index: 0) { onPick(nil) }
                    ForEach(Array(HomeCategory.all.enumerated()), id: \.element.id) { i, c in
                        item(c.name, on: selected == c, index: i + 1) { onPick(c) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                .padding(.bottom, 170)
            }
            .scrollIndicators(.hidden)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 58, height: 58)
                    .background(.white, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .scaleEffect(shown ? 1 : 0.4)
            .rotationEffect(.degrees(shown ? 0 : -90))
            .opacity(shown ? 1 : 0)
            // Clears the floating tab bar (62 pt tall), which is drawn above this screen.
            .padding(.bottom, 84)
            .accessibilityLabel("Close")
        }
        .onAppear {
            withAnimation(.spring(duration: 0.45, bounce: 0.35).delay(0.08)) { shown = true }
        }
    }

    private func item(_ name: String, on: Bool, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: on ? 22 : 19, weight: on ? .heavy : .medium))
                .foregroundStyle(on ? .white : Color(white: 0.66))
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 12)
        .animation(.easeOut(duration: 0.35).delay(0.03 + Double(index) * 0.018), value: shown)
    }
}
