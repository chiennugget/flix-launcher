import SwiftData
import SwiftUI

/// Seasons and episodes over the player; picking one switches to it.
struct EpisodePicker: View {
    let title: Title
    let playing: PlayRequest
    let onPick: (PlayRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(Keys.tmdbKey) private var tmdbKey = ""
    @Query private var progress: [WatchProgress]

    @State private var seasons: [SeasonSummary]
    @State private var season: Int
    @State private var episodes: [Episode] = []
    @State private var loading = false
    @State private var failed = false

    init(title: Title, seasons: [SeasonSummary], playing: PlayRequest, onPick: @escaping (PlayRequest) -> Void) {
        self.title = title
        self.playing = playing
        self.onPick = onPick
        _seasons = State(initialValue: seasons)
        // Start on the season that's playing, so the season task loads it straight away.
        _season = State(initialValue: playing.season ?? seasons.first?.seasonNumber ?? 1)
        let key = title.key
        _progress = Query(filter: #Predicate<WatchProgress> { $0.titleKey == key })
    }

    private var progressByKey: [String: WatchProgress] {
        Dictionary(progress.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if loading && episodes.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if failed {
                        HStack {
                            Text("Couldn't load episodes.").foregroundStyle(.secondary)
                            Button("Retry") { Task { await loadEpisodes() } }
                        }
                    }
                    ForEach(episodes) { ep in
                        let request = PlayRequest(title: title, season: ep.seasonNumber, episode: ep.episodeNumber)
                        let isPlaying = request.progressKey == playing.progressKey
                        Button {
                            if isPlaying { dismiss() } else { onPick(request) }
                        } label: {
                            EpisodeRow(episode: ep, progress: progressByKey[request.progressKey])
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(isPlaying ? Theme.accent.opacity(0.25) : Color.clear)
                        .id(request.progressKey)
                        .contextMenu {
                            let done = progressByKey[request.progressKey]?.isFinished == true
                            Button {
                                Library.setWatched(request, !done, runtimeMinutes: ep.runtime, in: context)
                            } label: {
                                Label(done ? "Mark as unwatched" : "Mark as watched",
                                      systemImage: done ? "eye.slash" : "checkmark.circle")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .onChange(of: episodes) {
                    // Bring the playing episode into view.
                    if season == playing.season { proxy.scrollTo(playing.progressKey, anchor: .center) }
                }
            }
            .navigationTitle(title.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if seasons.count > 1 {
                        Picker("Season", selection: $season) {
                            ForEach(seasons, id: \.seasonNumber) { s in
                                Text(s.name ?? "Season \(s.seasonNumber)").tag(s.seasonNumber)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: season) { await loadEpisodes() }
            .task { await loadSeasonsIfNeeded() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// The player may not have fetched the seasons yet.
    private func loadSeasonsIfNeeded() async {
        guard seasons.isEmpty, let client = TMDB.client(userKey: tmdbKey) else { return }
        let all = (try? await client.show(title.tmdbID).seasons) ?? []
        let regular = all.filter { $0.seasonNumber > 0 }
        seasons = regular.isEmpty ? all : regular
    }

    private func loadEpisodes() async {
        guard let client = TMDB.client(userKey: tmdbKey) else { return }
        let number = season
        loading = true
        failed = false
        defer { loading = false }
        do {
            let loaded = try await client.season(title.tmdbID, number).episodes
            if season == number { episodes = loaded }
        } catch {
            if season == number, episodes.isEmpty { failed = true }
        }
    }
}
