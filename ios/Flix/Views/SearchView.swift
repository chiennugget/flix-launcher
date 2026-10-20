import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var site: SiteService
    @AppStorage(Keys.tmdbKey) private var tmdbKey = ""
    @State private var query = ""
    @State private var results: [Title] = []
    @State private var error: String?
    @State private var visit: SiteVisit?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if TMDB.client(userKey: tmdbKey) == nil {
                        KeyMissingCard()
                    }
                    if !trimmed.isEmpty, site.searchURL(trimmed) != nil {
                        Button {
                            visit = SiteVisit(url: site.searchURL(trimmed))
                        } label: {
                            Label("Search \"\(trimmed)\" on the site", systemImage: "globe")
                        }
                        .padding(.horizontal)
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                    }
                    if trimmed.isEmpty {
                        Text("Search movies and shows")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        PosterGrid(entries: results.map { RowEntry(title: $0, caption: $0.year) })
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Movies, shows")
            .navigationDestination(for: Title.self) { TitleDetailView(title: $0) }
            .task(id: query) { await search() }
            .fullScreenCover(item: $visit) { PlayerScreen(visit: $0) }
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func search() async {
        let text = trimmed
        guard !text.isEmpty, let client = TMDB.client(userKey: tmdbKey) else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            results = try await client.search(text)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
