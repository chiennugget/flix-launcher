import SwiftData
import SwiftUI

@MainActor
final class NewHotModel: ObservableObject {
    @Published private(set) var soon: [Title] = []
    @Published private(set) var watching: [Title] = []
    @Published private(set) var topShows: [Title] = []
    @Published private(set) var topMovies: [Title] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var loadedKey: String?

    func load(key: String, force: Bool = false) async {
        guard let client = TMDB.client(userKey: key), force || loadedKey != key else { return }
        failed = false
        loading = true
        defer { loading = false }
        let today = HomeModel.today
        async let movies = try? client.titles("/movie/upcoming", ["region": "US"], type: .movie)
        async let shows = try? client.titles("/discover/tv", ["first_air_date.gte": today,
                                                               "sort_by": "popularity.desc",
                                                               "with_original_language": "en"], type: .tv)
        async let trending = try? client.titles("/trending/all/day")
        async let tv = try? client.titles("/trending/tv/day", type: .tv)
        async let mv = try? client.titles("/trending/movie/day", type: .movie)

        let upcoming = ((await movies ?? []) + (await shows ?? []))
            .filter { ($0.date ?? "") > today && $0.backdropPath != nil }
            .sorted { ($0.date ?? "") < ($1.date ?? "") }
        withAnimation(.easeOut(duration: 0.3)) {
            soon = Array(upcoming.prefix(16))
        }
        let t = await trending ?? []
        let s = await tv ?? []
        let m = await mv ?? []
        withAnimation(.easeOut(duration: 0.3)) {
            watching = Array(t.filter { $0.backdropPath != nil }.prefix(8))
            topShows = Array(s.filter { $0.backdropPath != nil }.prefix(10))
            topMovies = Array(m.filter { $0.backdropPath != nil }.prefix(10))
        }
        // Only count it as loaded if something came back, so a launch while
        // offline doesn't leave the tab empty for good.
        let empty = soon.isEmpty && watching.isEmpty && topShows.isEmpty && topMovies.isEmpty
        loadedKey = empty ? nil : key
        failed = empty
    }
}

struct NewHotView: View {
    enum Section: String, CaseIterable, Identifiable {
        case soon, watching, shows, movies
        var id: String { rawValue }
        var label: String {
            switch self {
            case .soon: return "Coming Soon"
            case .watching: return "Everyone's Watching"
            case .shows: return "Top 10 Shows"
            case .movies: return "Top 10 Movies"
            }
        }
    }

    @AppStorage(Keys.tmdbKey) private var tmdbKey = ""
    @StateObject private var model = NewHotModel()
    @State private var active: Section = .soon
    @State private var jumping = false
    private let space = "newHot"

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 100)
                        if TMDB.client(userKey: tmdbKey) == nil {
                            KeyMissingCard()
                        }
                        sectionView(.soon) {
                            ForEach(model.soon) { t in NewHotItem(title: t, lead: .date) }
                        }
                        sectionView(.watching, heading: "Everyone's Watching", icon: "flame.fill") {
                            ForEach(model.watching) { t in NewHotItem(title: t, lead: .none) }
                        }
                        sectionView(.shows, heading: "Top 10 Shows Today", top10: true) {
                            ForEach(Array(model.topShows.enumerated()), id: \.element.id) { i, t in
                                NewHotItem(title: t, lead: .rank(i + 1))
                            }
                        }
                        sectionView(.movies, heading: "Top 10 Movies Today", top10: true) {
                            ForEach(Array(model.topMovies.enumerated()), id: \.element.id) { i, t in
                                NewHotItem(title: t, lead: .rank(i + 1))
                            }
                        }
                        if model.loading && model.soon.isEmpty {
                            SkeletonRows()
                        } else if model.failed {
                            VStack(spacing: 10) {
                                Text("Couldn't load New & Hot.").font(.system(size: 17, weight: .bold))
                                Text("Check your connection and try again.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button("Retry") { Task { await model.load(key: tmdbKey, force: true) } }
                                    .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        }
                        Color.clear.frame(height: 110)
                    }
                }
                .coordinateSpace(name: space)
                .scrollIndicators(.hidden)
                .refreshable { await model.load(key: tmdbKey, force: true) }
                .onPreferenceChange(SectionTopsKey.self) { tops in
                    guard !jumping else { return }
                    let current = Section.allCases.last { (tops[$0.rawValue] ?? .infinity) <= 110 } ?? .soon
                    if current != active { withAnimation(.easeOut(duration: 0.2)) { active = current } }
                }
                header(proxy)
            }
        }
        .task(id: tmdbKey) { await model.load(key: tmdbKey) }
    }

    private func header(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New & Hot")
                .font(.system(size: 26, weight: .heavy))
                .padding(.horizontal, 16)
                .frame(height: 50)
            ScrollViewReader { pillProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Section.allCases) { s in
                            Button {
                                jumping = true
                                withAnimation(.easeOut(duration: 0.2)) { active = s }
                                withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(s.rawValue, anchor: .top) }
                                Task {
                                    try? await Task.sleep(for: .seconds(0.7))
                                    jumping = false
                                }
                            } label: {
                                pillLabel(s)
                            }
                            .buttonStyle(PressableStyle())
                            .id(s.rawValue)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onChange(of: active) {
                    withAnimation(.easeOut(duration: 0.3)) { pillProxy.scrollTo(active.rawValue, anchor: .center) }
                }
            }
            .padding(.bottom, 10)
        }
        .background {
            Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.6)).ignoresSafeArea(edges: .top)
        }
    }

    private func pillLabel(_ s: Section) -> some View {
        let on = active == s
        return HStack(spacing: 6) {
            switch s {
            case .soon: Image(systemName: "popcorn.fill").foregroundStyle(on ? Theme.accent : .white)
            case .watching: Image(systemName: "flame.fill").foregroundStyle(.orange)
            case .shows, .movies: Top10Badge(scale: 0.72)
            }
            Text(s.label)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(on ? .black : .white)
        .padding(.horizontal, 13)
        .frame(height: 33)
        .background(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(Material.ultraThinMaterial), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(on ? 0 : 0.2), lineWidth: 1))
    }

    @ViewBuilder
    private func sectionView<Content: View>(_ s: Section, heading: String? = nil, icon: String? = nil, top10: Bool = false,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let heading {
                HStack(spacing: 8) {
                    if let icon { Image(systemName: icon).foregroundStyle(.orange) }
                    if top10 { Top10Badge(scale: 1.05) }
                    Text(heading)
                }
                .font(.system(size: 21, weight: .heavy))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)
            }
            content()
        }
        .padding(.top, 6)
        .id(s.rawValue)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: SectionTopsKey.self,
                                       value: [s.rawValue: geo.frame(in: .named(space)).minY])
            }
        }
    }
}

private struct SectionTopsKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// One title in New & Hot: a date or rank on the left, artwork and details.
struct NewHotItem: View {
    enum Lead {
        case none, date, rank(Int)
    }

    let title: Title
    let lead: Lead

    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var context
    @Environment(\.zoomNamespace) private var zoom
    @Query private var items: [LibraryItem]

    init(title: Title, lead: Lead) {
        self.title = title
        self.lead = lead
        let key = title.key
        _items = Query(filter: #Predicate<LibraryItem> { $0.key == key })
    }

    private var inList: Bool { items.first?.inWatchlist == true }
    private var sourceID: String { "nh-\(title.key)" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            leadView
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    router.open(title, from: sourceID)
                } label: {
                    Color.clear
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay { PosterImage(path: title.backdropPath, name: title.name, size: "w780") }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .zoomSource(sourceID, in: zoom)
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                HStack(alignment: .center) {
                    Text(title.name)
                        .font(.system(size: 20, weight: .heavy))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if isUpcoming {
                        smallButton(inList ? "checkmark" : "plus", inList ? "In My List" : "My List") { toggleList() }
                        smallButton("info.circle", "Info") { router.open(title, from: sourceID) }
                    }
                }
                .padding(.top, 12)
                if isUpcoming, let when = comingLabel {
                    Text(when).font(.system(size: 14, weight: .medium)).foregroundStyle(Color(white: 0.73)).padding(.top, 10)
                }
                if !title.overview.isEmpty {
                    Text(title.overview)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(white: 0.66))
                        .lineLimit(4)
                        .padding(.top, 6)
                }
                let tags = Genres.tags(title.genreIDs)
                if !tags.isEmpty {
                    Text(tags.joined(separator: " • "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.9))
                        .padding(.top, 8)
                }
                if !isUpcoming {
                    HStack(spacing: 10) {
                        wideButton(inList ? "checkmark" : "plus", "My List", white: false) { toggleList() }
                        wideButton("play.fill", "Play", white: true) { router.play(request) }
                    }
                    .padding(.top, 14)
                }
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 38)
    }

    private var isUpcoming: Bool { (title.date ?? "") > HomeModel.today }

    private var request: PlayRequest {
        title.type == .tv ? PlayRequest(title: title, season: 1, episode: 1) : PlayRequest(title: title)
    }

    private var comingLabel: String? {
        guard let date = parsedDate else { return nil }
        return "Coming " + date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var parsedDate: Date? {
        guard let s = title.date else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    @ViewBuilder
    private var leadView: some View {
        switch lead {
        case .none:
            Color.clear.frame(width: 8)
        case .date:
            VStack(spacing: 0) {
                Text(parsedDate?.formatted(.dateTime.month(.abbreviated)).uppercased() ?? "")
                    .font(.system(size: 12.5, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Color(white: 0.6))
                Text(parsedDate?.formatted(.dateTime.day()) ?? "")
                    .font(.system(size: 30, weight: .heavy))
            }
            .frame(width: 52)
        case .rank(let n):
            Text("\(n)")
                .font(.system(size: 54, weight: .black))
                .foregroundStyle(.clear)
                .overlay {
                    OutlinedDigits(text: "\(n)")
                }
                .frame(width: 52)
        }
    }

    private func smallButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 21)).contentTransition(.symbolEffect(.replace))
                Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color(white: 0.73))
            }
            .frame(minWidth: 48)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }

    private func wideButton(_ icon: String, _ label: String, white: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).contentTransition(.symbolEffect(.replace))
                Text(label)
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(white ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(white ? Color.white : Color(white: 0.18), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }

    private func toggleList() {
        let entry = Library.item(for: title, in: context)
        withAnimation(.spring(duration: 0.35, bounce: 0.4)) {
            entry.inWatchlist.toggle()
            entry.watchlistAddedAt = .now
        }
    }
}

/// White outlined digits for New & Hot's Top 10 ranks.
private struct OutlinedDigits: View {
    let text: String

    var body: some View {
        let t = Text(text).font(.system(size: 54, weight: .black))
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * .pi / 4
                t.foregroundStyle(.white).offset(x: cos(angle) * 1.5, y: sin(angle) * 1.5)
            }
            t.foregroundStyle(.black)
        }
    }
}
