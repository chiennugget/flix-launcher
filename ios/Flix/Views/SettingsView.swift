import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var site: SiteService
    @Environment(\.modelContext) private var context
    @AppStorage(Keys.tmdbKey) private var tmdbKey = ""
    @AppStorage(Keys.configURL) private var configURL = ""
    @AppStorage(Keys.autoplayNext) private var autoplayNext = true
    @AppStorage(Keys.nativeFullscreen) private var nativeFullscreen = false
    @State private var visit: SiteVisit?
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Address", value: site.domain)
                    HStack {
                        Text(site.status).font(.footnote).foregroundStyle(.secondary)
                        if site.checking {
                            Spacer()
                            ProgressView()
                        }
                    }
                    if let updated = site.updated {
                        LabeledContent("Last moved", value: updated.formatted(date: .abbreviated, time: .omitted))
                    }
                    Button("Check again") { Task { await site.refresh() } }
                        .disabled(site.checking)
                    Button("Open the site") { visit = SiteVisit() }
                } header: {
                    Text("Site")
                } footer: {
                    Text("The address comes from domain.json in your flix-launcher repo, which the GitHub checker updates every 4 hours. If it looks dead, the app follows the mirrors itself.")
                }

                Section {
                    SecureField("API key or read access token", text: $tmdbKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if tmdbKey.isEmpty, !TMDB.bundledKey.isEmpty {
                        Text("Using the key built into this build.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Link("Get a free key", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                } header: {
                    Text("Movie info (TMDB)")
                } footer: {
                    Text("Posters, descriptions, episodes and search come from The Movie Database.")
                }

                Section {
                    LabeledContent("Movie link", value: describe(site.paths.movie))
                    LabeledContent("Episode link", value: describe(site.paths.tv))
                    LabeledContent("Search link", value: describe(site.paths.search))
                } header: {
                    Text("Site links")
                } footer: {
                    Text("Set these in domain.json under \"paths\" so Play opens the exact page. Until then Play searches the site, and the app remembers the page each time a video starts playing.")
                }

                Section {
                    Toggle("Autoplay next episode", isOn: $autoplayNext)
                    Toggle("Use iPhone fullscreen player", isOn: $nativeFullscreen)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Autoplay: near the end of an episode, a 10-second countdown starts the next one on the same player.\n\nFullscreen: off keeps the site's player and its controls (captions, quality) in fullscreen. On uses the iPhone's own player, which has picture-in-picture but can show subtitles twice. Applies the next time you open a video.")
                }

                Section("Advanced") {
                    TextField("Custom domain.json URL", text: $configURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Forget remembered links") { forgetLinks() }
                    Button("Clear watch history", role: .destructive) { confirmClear = true }
                }

                Section {
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Clear watch history and resume points?", isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("Clear", role: .destructive) { clearHistory() }
            }
            .fullScreenCover(item: $visit) { PlayerScreen(visit: $0) }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func describe(_ template: String?) -> String {
        let t = template?.trimmingCharacters(in: .whitespaces) ?? ""
        return t.isEmpty ? "Not set" : t
    }

    private func forgetLinks() {
        for progress in (try? context.fetch(FetchDescriptor<WatchProgress>())) ?? [] {
            progress.sitePath = nil
        }
    }

    private func clearHistory() {
        try? context.delete(model: WatchProgress.self)
        for item in (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? [] {
            item.inHistory = false
            item.resumeLabel = nil
            item.resumeFraction = 0
            item.lastSeason = nil
            item.lastEpisode = nil
        }
    }
}
