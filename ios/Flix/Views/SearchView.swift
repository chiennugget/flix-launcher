import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var site: SiteService
    @EnvironmentObject private var router: Router
    @Environment(\.zoomNamespace) private var zoom
    @AppStorage(Keys.tmdbKey) private var tmdbKey = ""
    @State private var query = ""
    @State private var results: [Title] = []
    @State private var recommended: [Title] = []
    @State private var searched = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 62)
                    if TMDB.client(userKey: tmdbKey) == nil {
                        KeyMissingCard().padding(.top, 12)
                    }
                    if trimmed.isEmpty {
                        recommendedList
                    } else {
                        resultsView
                    }
                    Color.clear.frame(height: 110)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            searchBar
        }
        .task(id: query) { await search() }
        .task(id: tmdbKey) { await loadRecommended() }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var searchBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color(white: 0.6))
                TextField("Search shows and movies", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color(white: 0.6))
                    }
                    .accessibilityLabel("Clear")
                }
            }
            .font(.system(size: 16, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            if focused {
                Button("Cancel") {
                    query = ""
                    focused = false
                }
                .font(.system(size: 16, weight: .medium))
                .padding(.leading, 12)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.1), value: focused)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background {
            Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.65)).ignoresSafeArea(edges: .top)
        }
    }

    @ViewBuilder
    private var recommendedList: some View {
        if !recommended.isEmpty {
            Text("Recommended TV Shows & Movies")
                .font(.system(size: 19, weight: .heavy))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            LazyVStack(spacing: 6) {
                ForEach(recommended) { t in
                    let id = "rec-\(t.key)"
                    HStack(spacing: 12) {
                        Button {
                            router.open(t, from: id)
                        } label: {
                            HStack(spacing: 12) {
                                Color.clear
                                    .frame(width: 146, height: 82)
                                    .overlay { PosterImage(path: t.backdropPath ?? t.posterPath, name: t.name, size: "w300") }
                                    .clipped()
                                    .zoomSource(id, in: zoom)
                                Text(t.name)
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        Button {
                            router.play(t.type == .tv ? PlayRequest(title: t, season: 1, episode: 1) : PlayRequest(title: t))
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        }
                        .buttonStyle(PressableStyle(scale: 0.88))
                        .padding(.trailing, 16)
                        .accessibilityLabel("Play \(t.name)")
                    }
                    .background(Color(white: 0.08))
                }
            }
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        if site.searchURL(trimmed) != nil {
            Button {
                router.visit = SiteVisit(url: site.searchURL(trimmed))
            } label: {
                Label("Search “\(trimmed)” on the site", systemImage: "globe")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        if let error {
            Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 10)
        }
        if !results.isEmpty {
            Text("Movies & TV")
                .font(.system(size: 19, weight: .heavy))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            PosterGrid(id: "search", titles: results)
                .transition(.opacity)
        } else if searched {
            VStack(spacing: 8) {
                Text("Oh darn. We don't have that.").font(.system(size: 20, weight: .bold))
                Text("Try searching for another movie, show, actor, director or genre.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color(white: 0.6))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 70)
        }
    }

    private func loadRecommended() async {
        guard recommended.isEmpty, let client = TMDB.client(userKey: tmdbKey) else { return }
        var list = (try? await client.titles("/trending/all/week")) ?? []
        // One retry: this runs at first launch, often before the network is up.
        if list.isEmpty, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            list = (try? await client.titles("/trending/all/week")) ?? []
        }
        withAnimation(.easeOut(duration: 0.3)) { recommended = Array(list.prefix(16)) }
    }

    private func search() async {
        let text = trimmed
        guard !text.isEmpty, let client = TMDB.client(userKey: tmdbKey) else {
            results = []
            searched = false
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let found = try await client.search(text)
            withAnimation(.easeOut(duration: 0.25)) {
                results = found.filter { $0.posterPath != nil }
                searched = true
            }
            error = nil
        } catch is CancellationError {
        } catch {
            // Don't leave the previous search's results under the new query.
            results = []
            searched = false
            self.error = error.localizedDescription
        }
    }
}
