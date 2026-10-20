import SwiftData
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "house.fill") }
            SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
            MyListView().tabItem { Label("My List", systemImage: "rectangle.stack.fill") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

@MainActor
final class HomeModel: ObservableObject {
    struct Row: Identifiable {
        let id: String
        let name: String
        let items: [Title]
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var hero: Title?
    @Published private(set) var error: String?
    private var loadedKey: String?

    private static let specs: [(id: String, name: String, path: String, query: [String: String], type: MediaType?)] = [
        ("trending", "Trending Now", "/trending/all/week", [:], nil),
        ("popular-movies", "Popular Movies", "/movie/popular", [:], .movie),
        ("popular-tv", "Popular Shows", "/tv/popular", [:], .tv),
        ("top-movies", "Top Rated Movies", "/movie/top_rated", [:], .movie),
        ("top-tv", "Top Rated Shows", "/tv/top_rated", [:], .tv),
        ("action", "Action", "/discover/movie", ["with_genres": "28"], .movie),
        ("comedy", "Comedy", "/discover/movie", ["with_genres": "35"], .movie),
        ("crime-tv", "Crime Shows", "/discover/tv", ["with_genres": "80"], .tv),
        ("horror", "Horror", "/discover/movie", ["with_genres": "27"], .movie),
        ("scifi-tv", "Sci-Fi & Fantasy Shows", "/discover/tv", ["with_genres": "10765"], .tv),
        ("animation", "Animation", "/discover/movie", ["with_genres": "16"], .movie),
    ]

    func load(key: String, force: Bool = false) async {
        guard let client = TMDB.client(userKey: key) else {
            rows = []
            hero = nil
            error = nil
            loadedKey = nil
            return
        }
        if !force, loadedKey == key, !rows.isEmpty { return }
        loadedKey = key
        error = nil

        var loaded: [(Int, Row)] = []
        var failure: Error?
        await withTaskGroup(of: (Int, Row?, Error?).self) { group in
            for (index, spec) in Self.specs.enumerated() {
                group.addTask {
                    do {
                        var query = spec.query
                        if spec.path.hasPrefix("/discover") { query["sort_by"] = "popularity.desc" }
                        let items = try await client.titles(spec.path, query, type: spec.type)
                        return (index, Row(id: spec.id, name: spec.name, items: items), nil)
                    } catch {
                        return (index, nil, error)
                    }
                }
            }
            for await (index, row, err) in group {
                if let row, !row.items.isEmpty {
                    loaded.append((index, row))
                    loaded.sort { $0.0 < $1.0 }
                    rows = loaded.map(\.1)
                } else if failure == nil {
                    failure = err
                }
            }
        }
        hero = rows.first?.items.first { $0.backdropPath != nil }
        if rows.isEmpty, let failure { error = failure.localizedDescription }
    }
}

struct HomeView: View {
    @EnvironmentObject private var site: SiteService
    @AppStorage(Keys.tmdbKey) private var tmdbKey = ""
    @StateObject private var model = HomeModel()
    @State private var visit: SiteVisit?

    @Query(filter: #Predicate<LibraryItem> { $0.inHistory == true },
           sort: \LibraryItem.lastWatchedAt, order: .reverse)
    private var history: [LibraryItem]

    @Query(filter: #Predicate<LibraryItem> { $0.inWatchlist == true },
           sort: \LibraryItem.watchlistAddedAt, order: .reverse)
    private var watchlist: [LibraryItem]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if let hero = model.hero {
                        HeroView(title: hero)
                    }
                    if !history.isEmpty {
                        TitleRow(name: "Continue Watching", entries: history.prefix(20).map {
                            RowEntry(title: $0.asTitle, caption: $0.resumeLabel, fraction: $0.resumeFraction)
                        })
                    }
                    if !watchlist.isEmpty {
                        TitleRow(name: "My List", entries: watchlist.prefix(20).map { RowEntry(title: $0.asTitle) })
                    }
                    if TMDB.client(userKey: tmdbKey) == nil {
                        KeyMissingCard()
                    }
                    ForEach(model.rows) { row in
                        TitleRow(name: row.name, entries: row.items.map { RowEntry(title: $0) })
                    }
                    if let error = model.error {
                        Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Flix")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        visit = SiteVisit()
                    } label: {
                        Image(systemName: "globe")
                    }
                    .accessibilityLabel("Open site")
                }
            }
            .navigationDestination(for: Title.self) { TitleDetailView(title: $0) }
            .task(id: tmdbKey) { await model.load(key: tmdbKey) }
            .refreshable {
                await model.load(key: tmdbKey, force: true)
                await site.refresh()
            }
            .fullScreenCover(item: $visit) { PlayerScreen(visit: $0) }
        }
    }
}
