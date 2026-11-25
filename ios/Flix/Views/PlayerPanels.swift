import SwiftData
import SwiftUI

enum PlayerPanel: Equatable {
    case speed, audio, episodes
}

/// A dark glass panel that slides up over the lower part of the video.
struct PlayerSheet<Content: View>: View {
    var fraction: CGFloat = 0.6
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                    .transition(.opacity)
                content()
                    .frame(maxWidth: .infinity)
                    .frame(height: geo.size.height * fraction, alignment: .top)
                    .padding(.top, 18)
                    .background {
                        Rectangle().fill(.ultraThinMaterial)
                            .overlay(Color.black.opacity(0.55))
                            .ignoresSafeArea(edges: [.bottom, .horizontal])
                    }
                    .overlay(alignment: .topTrailing) {
                        Button(action: onClose) {
                            Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        .padding(.trailing, 12)
                        .accessibilityLabel("Close")
                    }
                    .transition(.move(edge: .bottom))
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

struct SpeedPanel: View {
    let rate: Double
    let onPick: (Double) -> Void
    let onClose: () -> Void

    static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5]

    var body: some View {
        PlayerSheet(fraction: 0.42, onClose: onClose) {
            VStack(spacing: 26) {
                Text("Playback Speed").font(.system(size: 18, weight: .bold))
                HStack(spacing: 0) {
                    ForEach(Array(Self.speeds.enumerated()), id: \.offset) { i, speed in
                        let on = abs(speed - rate) < 0.01
                        Button {
                            onPick(speed)
                        } label: {
                            VStack(spacing: 16) {
                                Circle()
                                    .fill(on ? Color.white : Color(white: 0.55))
                                    .frame(width: 12, height: 12)
                                    .scaleEffect(on ? 2 : 1)
                                    .animation(.spring(duration: 0.35, bounce: 0.45), value: on)
                                Text(speed == 1 ? "1x (Normal)" : "\(Self.label(speed))x")
                                    .font(.system(size: 14, weight: on ? .bold : .medium))
                                    .foregroundStyle(on ? .white : Color(white: 0.66))
                                    .fixedSize()
                            }
                            .frame(width: 80)
                        }
                        .buttonStyle(.plain)
                        if i < Self.speeds.count - 1 { Spacer(minLength: 0) }
                    }
                }
                .background(alignment: .top) {
                    Rectangle().fill(Color(white: 0.35)).frame(height: 2).padding(.horizontal, 40).padding(.top, 5)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 30)
            }
        }
    }

    static func label(_ speed: Double) -> String {
        String(format: "%g", speed)
    }
}

struct AudioSubtitlesPanel: View {
    let tracks: MediaTracks?
    let onText: (Int) -> Void
    let onAudio: (Int) -> Void
    let onSiteControls: () -> Void
    let onClose: () -> Void

    var body: some View {
        PlayerSheet(fraction: 0.64, onClose: onClose) {
            if let tracks {
                if tracks.text.isEmpty && tracks.audio.count <= 1 {
                    fallback
                } else {
                    HStack(alignment: .top, spacing: 40) {
                        column("Audio") {
                            if tracks.audio.isEmpty {
                                row("Default", on: true) {}
                            }
                            ForEach(tracks.audio) { t in
                                row(t.l, on: t.on) { onAudio(t.i) }
                            }
                        }
                        column("Subtitles") {
                            row("Off", on: !tracks.text.contains { $0.on }) { onText(-1) }
                            ForEach(tracks.text) { t in
                                row(t.l, on: t.on) { onText(t.i) }
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                }
            } else {
                ProgressView().padding(.top, 30)
            }
        }
    }

    private var fallback: some View {
        VStack(spacing: 12) {
            Text("Subtitles are built into this player").font(.system(size: 17, weight: .bold))
            Text("Switch to the site's own controls to turn captions on or pick a language. Tap “Flix controls” to come back.")
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button(action: onSiteControls) {
                Text("Use the site's controls")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 6)
        }
        .padding(.horizontal, 40)
    }

    private func column<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 17, weight: .bold))
            ScrollView {
                VStack(alignment: .leading, spacing: 4) { rows() }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .opacity(on ? 1 : 0)
                    .scaleEffect(on ? 1 : 0.4)
                Text(label)
                    .font(.system(size: 15, weight: on ? .bold : .medium))
                    .foregroundStyle(on ? .white : Color(white: 0.66))
            }
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3, bounce: 0.4), value: on)
    }
}

/// Seasons and episodes over the video, as a sideways strip of cards.
struct EpisodesPanel: View {
    let title: Title
    let seasons: [SeasonSummary]
    let playing: PlayRequest
    let onPick: (PlayRequest) -> Void
    let onClose: () -> Void

    @AppStorage(Keys.tmdbKey) private var tmdbKey = ""
    @Query private var progress: [WatchProgress]
    @State private var season: Int
    @State private var episodes: [Episode] = []
    @State private var episodesSeason: Int?
    @State private var loading = false
    @State private var failed = false

    init(title: Title, seasons: [SeasonSummary], playing: PlayRequest,
         onPick: @escaping (PlayRequest) -> Void, onClose: @escaping () -> Void) {
        self.title = title
        self.seasons = seasons
        self.playing = playing
        self.onPick = onPick
        self.onClose = onClose
        _season = State(initialValue: playing.season ?? seasons.first?.seasonNumber ?? 1)
        let key = title.key
        _progress = Query(filter: #Predicate<WatchProgress> { $0.titleKey == key })
    }

    private var progressByKey: [String: WatchProgress] {
        Dictionary(progress.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.55)).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    if seasons.count > 1 {
                        Menu {
                            Picker("Season", selection: $season) {
                                ForEach(seasons, id: \.seasonNumber) { s in
                                    Text(s.name ?? "Season \(s.seasonNumber)").tag(s.seasonNumber)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(seasons.first { $0.seasonNumber == season }?.name ?? "Season \(season)")
                                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Color.white.opacity(0.18), in: Capsule())
                        }
                    } else {
                        Text(title.name).font(.system(size: 17, weight: .bold))
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close")
                }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            if loading && episodes.isEmpty {
                                ProgressView().frame(width: 168, height: 94)
                            } else if failed {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Couldn't load episodes.").font(.system(size: 14, weight: .semibold))
                                    Button("Retry") { Task { await load() } }
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .frame(height: 94)
                            }
                            ForEach(episodes) { ep in
                                card(ep).id(ep.episodeNumber)
                            }
                        }
                    }
                    .onChange(of: episodes) {
                        if season == playing.season, let e = playing.episode {
                            proxy.scrollTo(e, anchor: .center)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 14)
        }
        .environment(\.colorScheme, .dark)
        .task(id: season) { await load() }
    }

    private func card(_ ep: Episode) -> some View {
        let request = PlayRequest(title: title, season: ep.seasonNumber, episode: ep.episodeNumber)
        let isPlaying = request.progressKey == playing.progressKey
        let saved = progressByKey[request.progressKey]
        return Button {
            if isPlaying { onClose() } else { onPick(request) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .frame(width: 168, height: 94)
                    .overlay { PosterImage(path: ep.stillPath, name: "E\(ep.episodeNumber)", size: "w300") }
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.5), in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1.2))
                    }
                    .overlay(alignment: .bottom) {
                        if let saved, saved.fraction > 0 { ProgressBar(fraction: saved.fraction) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white, lineWidth: isPlaying ? 2 : 0))
                Text("\(ep.episodeNumber). \(ep.name ?? "Episode \(ep.episodeNumber)")")
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                if let runtime = ep.runtime, runtime > 0 {
                    Text("\(runtime)m").font(.system(size: 11.5)).foregroundStyle(Color(white: 0.6))
                }
                Text(ep.overview ?? "")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(white: 0.7))
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 168, alignment: .leading)
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .accessibilityLabel("Episode \(ep.episodeNumber), \(ep.name ?? "")")
        .accessibilityValue(isPlaying ? "Now playing" : (saved?.isFinished == true ? "Watched" : ""))
    }

    private func load() async {
        guard let client = TMDB.client(userKey: tmdbKey) else { return }
        let number = season
        if episodesSeason != number { episodes = [] }
        loading = true
        failed = false
        defer { loading = false }
        do {
            let loaded = try await client.season(title.tmdbID, number).episodes
            guard season == number else { return }
            withAnimation(.easeOut(duration: 0.25)) { episodes = loaded }
            episodesSeason = number
        } catch is CancellationError {
        } catch {
            if season == number, episodes.isEmpty { failed = true }
        }
    }
}

/// Red Netflix scrubber with the time left; shows the time under your finger while dragging.
struct PlayerScrubber: View {
    let time: Double
    let duration: Double
    @Binding var scrubbing: Double?
    let onSeek: (Double) -> Void

    var body: some View {
        HStack(spacing: 14) {
            GeometryReader { geo in
                let width = geo.size.width
                let shownTime = scrubbing ?? time
                let fraction = duration > 0 ? min(max(shownTime / duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                    Capsule().fill(Theme.accent).frame(width: max(0, width * fraction), height: 4)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 16, height: 16)
                        .scaleEffect(scrubbing == nil ? 1 : 1.5)
                        .offset(x: width * fraction - 8)
                        .animation(.spring(duration: 0.25, bounce: 0.4), value: scrubbing == nil)
                    if let s = scrubbing {
                        Text(Format.time(s))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.65), in: Capsule())
                            .fixedSize()
                            .offset(x: min(max(width * fraction - 30, 0), max(width - 60, 0)), y: -30)
                    }
                }
                .frame(width: width, height: 30)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0, width > 0 else { return }
                            scrubbing = min(max(value.location.x / width, 0), 1) * duration
                        }
                        .onEnded { _ in
                            if let s = scrubbing { onSeek(s) }
                        }
                )
            }
            .frame(height: 30)
            Text(Format.time(max(0, duration - (scrubbing ?? time))))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .frame(minWidth: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Format.time(time)) of \(Format.time(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(duration, time + 10))
            case .decrement: onSeek(max(0, time - 10))
            @unknown default: break
            }
        }
    }
}

/// Vertical brightness control on the left edge, like Netflix's.
struct BrightnessSlider: View {
    @Binding var value: CGFloat
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max").font(.system(size: 17))
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.3))
                    Capsule().fill(.white).frame(height: geo.size.height * value)
                }
                .frame(width: 4)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        guard geo.size.height > 0 else { return }
                        value = min(max(1 - drag.location.y / geo.size.height, 0.02), 1)
                        onChange()
                    }
                )
            }
        }
        .frame(width: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(value * 100))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0.02, value - 0.1)
            @unknown default: break
            }
            onChange()
        }
    }
}
