import CryptoKit
import AVFoundation
import Foundation
import SwiftUI
import Combine
#if os(iOS)
import LocalAuthentication
import Security
import UIKit
import AVKit
import CoreLocation
#else
import AppKit
#endif

enum BreeAppearanceTheme: String, CaseIterable, Identifiable {
    case burntOrange, oceanBlue, violet, emerald
    var id: String { rawValue }
    var title: String {
        switch self {
        case .burntOrange: "Burnt Orange"
        case .oceanBlue: "Ocean Blue"
        case .violet: "Violet"
        case .emerald: "Emerald"
        }
    }
    var colors: (accent: Color, bright: Color, glass: Color, surface: Color) {
        switch self {
        case .burntOrange:
            (Color(red: 0.78, green: 0.29, blue: 0.10), Color(red: 1.0, green: 0.57, blue: 0.28), Color(red: 0.82, green: 0.34, blue: 0.13).opacity(0.42), Color(red: 0.15, green: 0.075, blue: 0.045))
        case .oceanBlue:
            (Color(red: 0.05, green: 0.40, blue: 0.68), Color(red: 0.35, green: 0.78, blue: 1.0), Color(red: 0.04, green: 0.30, blue: 0.52), Color(red: 0.025, green: 0.075, blue: 0.13))
        case .violet:
            (Color(red: 0.39, green: 0.22, blue: 0.65), Color(red: 0.75, green: 0.58, blue: 1.0), Color(red: 0.31, green: 0.16, blue: 0.55), Color(red: 0.075, green: 0.045, blue: 0.13))
        case .emerald:
            (Color(red: 0.08, green: 0.40, blue: 0.30), Color(red: 0.38, green: 0.86, blue: 0.67), Color(red: 0.06, green: 0.32, blue: 0.23), Color(red: 0.025, green: 0.09, blue: 0.065))
        }
    }
}

enum BreeHomePalette {
    private static var colors: BreeAppearanceTheme {
        BreeAppearanceTheme(rawValue: UserDefaults.standard.string(forKey: "BreeMusic.AppearanceTheme") ?? "burntOrange") ?? .burntOrange
    }
    static var burntOrange: Color { colors.colors.accent }
    static var lightOrange: Color { colors.colors.bright }
    static var glassTint: Color { colors.colors.glass }
    static var surface: Color { colors.colors.surface }
    static let slateLabel = Color(red: 0.55, green: 0.61, blue: 0.69)
    static let separator = Color.white.opacity(0.09)
}

struct ContentView: View {
    private enum HomeTab: Hashable { case home, albums, artists, settings }
    private static let tailnetServerAddress = "http://bree.tail086392.ts.net:4533"
    private static let lastKnownTailnetIP = "http://100.120.162.53:4533"
    @FocusState private var isSearchFieldFocused: Bool
    @AppStorage("BreeMusic.AppearanceTheme") private var appearanceThemeRaw = BreeAppearanceTheme.burntOrange.rawValue
    @AppStorage("BreeMusic.StreamQuality") private var streamQualityRaw = BreeStreamQuality.automatic.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var serverAddress = "http://bree.tail086392.ts.net:4533"
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var connectionResult: ConnectionResult?
    @State private var albums: [NavidromeAlbum] = []
    @State private var artistDirectory: [NavidromeArtistRecord] = []
    @State private var searchText = ""
    @State private var searchResults: NavidromeSearchResults?
    @State private var showAllSearchArtists = false
    @State private var showAllSearchTracks = false
    @State private var lyricSearchMatches: [NavidromeTrack] = []
    @State private var isSearchingLyrics = false
    @State private var lyricsSearchTask: Task<Void, Never>?
    @State private var lyricTextCache: [String: String] = [:]
    @State private var lyricsKeywordIndex: [String: Set<String>] = [:]
    @State private var lyricsSearchedQuery: String?
    @State private var isSearchingLibrary = false
    @State private var searchTask: Task<Void, Never>?
    @State private var albumByTrackID: [String: NavidromeAlbum] = [:]
    @State private var mostPlayed: [MostPlayedTrackRecord] = []
    @State private var listeningHistory: [ListeningHistoryEvent] = []
    @State private var recentOpenedAlbums: [RecentAlbumOpen] = []
    @State private var recentSearchedArtists = UserDefaults.standard.stringArray(forKey: "BreeMusic.RecentArtists") ?? []
    @State private var randomHomepageArtists: [String] = []
    @State private var recentMixHistory: [RecentMixPlayback] = []
    @State private var showingRecap = false
    @State private var isStartingRadio = false
    @State private var moodPlaylists: [String: [NavidromeTrack]] = [:]
    @State private var genrePlaylists: [String: [NavidromeTrack]] = [:]
    @State private var activeMoodMix: String?
    @State private var selectedMoodMixName: String?
    @State private var showingMoodMixDetail = false
    @State private var activeGenre: String?
    @State private var selectedArtistGenre: String?
    @State private var moodPlaylistsLoaded = false
    @State private var isLoadingMoodPlaylists = false
    @State private var moodAlbumsProcessed = 0
    @State private var moodAlbumsTotal = 0
    @State private var moodPlaylistStatus: [String: String] = [:]
    #if os(iOS)
    @State private var audioAnalysisByTrackID: [String: BreeTrackAudioAnalysis] = [:]
    @State private var isAnalyzingLibraryAudio = false
    @State private var audioAnalysisTracksProcessed = 0
    @State private var moodRefreshBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif
    @State private var favoriteTrackIDs = Set(UserDefaults.standard.stringArray(forKey: "BreeMusic.Favorites") ?? [])
    @State private var likedTrackIDs = Set(UserDefaults.standard.stringArray(forKey: "BreeMusic.Likes") ?? [])
    @State private var dislikedTrackIDs = Set(UserDefaults.standard.stringArray(forKey: "BreeMusic.Dislikes") ?? [])
    @State private var selectedArtistName: String?
    @State private var selectedArtistInfo: NavidromeArtistInfo?
    @State private var artistInfoCache: [String: NavidromeArtistInfo] = [:]
    @State private var selectedAlbumInfo: NavidromeAlbumInfo?
    @State private var albumInfoCache: [String: NavidromeAlbumInfo] = [:]
    @State private var expandedArtistAlbumID: String?
    @State private var isLoadingAlbumInfo = false
    @State private var albumSortOrder: AlbumSortOrder = .album
    @State private var selectedAlbum: NavidromeAlbum?
    @State private var tracks: [NavidromeTrack] = []
    @State private var isLoadingTracks = false
    @State private var trackLoadError: String?
    #if os(iOS)
    @State private var nowPlaying = BreeNowPlayingSession()
    @StateObject private var weatherLocation = BreeWeatherLocation()
    @StateObject private var networkPathMonitor = BreeNetworkPathMonitor()
    #else
    @State private var player: AVPlayer?
    #endif
    @State private var currentTrackID: String?
    @State private var startingTrackID: String?
    @State private var isPaused = false
    @State private var playbackMessage: String?
    @State private var showingEqualizer = false
    @State private var showingSettings = false
    @State private var showingProfile = false
    @State private var showingAlbumDetail = false
    @State private var showingArtistBrowser = false
    @State private var showingNowPlaying = false
    @State private var selectedHomeTab: HomeTab = .home
    @State private var openPlayerAfterTrackStarts = false
    @State private var showingLyrics = false
    @State private var lyricLines: [BreeLyricLine] = []
    @State private var lyricsLoading = false
    @State private var pendingLyricsSearch: PendingLyricsSearch?
    @State private var lyricSearchTargetLineID: Int?
    #if os(iOS)
    @State private var isLocked = true
    @State private var unlockMessage: String?
    @State private var relockTask: Task<Void, Never>?
    #endif

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedStreamBitRate: Int {
        let quality = BreeStreamQuality(rawValue: streamQualityRaw) ?? .automatic
        #if os(iOS)
        return quality.bitRate(for: networkPathMonitor.connection)
        #else
        return quality.bitRate(for: .unknown)
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 12) {
                        Image("BreeMusicLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BreeMusic")
                                .font(.title2.bold())
                            Text("BEEP, BEEP BABY!")
                                .font(.caption2.weight(.semibold))
                                .tracking(1.5)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        #if os(iOS)
                        HStack(spacing: 5) {
                            Image(systemName: weatherLocation.conditionSymbol)
                                .font(.caption)
                                .foregroundStyle(BreeHomePalette.lightOrange.opacity(0.9))
                            Text(weatherLocation.temperatureLabel ?? "—°")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial.opacity(0.35), in: Capsule())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(weatherLocation.conditionDescription), \(weatherLocation.temperatureLabel ?? "temperature unavailable")")
                        #endif
                    }
                    .padding(.top, 12)

                    if selectedHomeTab == .home {
                    if connectionResult?.isSuccess == true {
                        if !hasActiveSearch {
                            Text("Wagwan, Bree")
                                .font(.title2.weight(.semibold))
                                .padding(.top, 2)
                        }
                    } else if let connectionResult {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(connectionResult.title, systemImage: connectionResult.symbol)
                                .font(.subheadline.bold())
                                .foregroundStyle(.red)
                            Text(connectionResult.detail)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                            Button { showingProfile = true } label: {
                                Label("Edit Navidrome login", systemImage: "person.crop.circle")
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                        }
                        .padding(16)
                        .background(BreeHomePalette.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(BreeHomePalette.separator, lineWidth: 1)
                        }
                    }

                    if connectionResult?.isSuccess == true {
                        librarySearchSection
                        if !hasActiveSearch {
                            breeRadioSection
                            moodPlaylistsSection
                        }
                    }

                    if connectionResult?.isSuccess == true, !hasActiveSearch, !recentlyPlayedItems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recently Played")
                                .font(.title3.bold())
                                .foregroundStyle(BreeHomePalette.lightOrange)
                                .frame(maxWidth: .infinity, alignment: .center)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                                ForEach(recentlyPlayedItems) { item in
                                    Button {
                                        if let track = item.track { playFromHistory(track) }
                                        else if let album = item.album { openAlbum(album) }
                                    } label: {
                                        HStack(spacing: 10) {
                                            if let track = item.track {
                                                albumTile(track.album, size: 54)
                                            } else if let album = item.album {
                                                albumTile(album, size: 54)
                                            } else {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(LinearGradient(colors: [BreeHomePalette.burntOrange, BreeHomePalette.lightOrange.opacity(0.55)], startPoint: .bottomLeading, endPoint: .topTrailing))
                                                    Image(systemName: item.mixName == "BreeMusic Radio" ? "dot.radiowaves.left.and.right" : "music.note.list")
                                                        .font(.title3.weight(.semibold))
                                                        .foregroundStyle(.white)
                                                }
                                                .frame(width: 54, height: 54)
                                            }
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.title)
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                Text(item.track != nil ? "TRACK" : item.album != nil ? "ALBUM" : "MIX")
                                                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                                                    .tracking(1.1)
                                                    .foregroundStyle(BreeHomePalette.slateLabel)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(maxWidth: .infinity)
                                        .padding(9)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                                        .contentShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    if currentTrackID == nil, let playbackMessage {
                        HStack {
                            Image(systemName: "waveform.circle.fill").font(.title).foregroundStyle(BreeHomePalette.lightOrange)
                            VStack(alignment: .leading) {
                                Text("NOW PLAYING").font(.caption2.bold()).foregroundStyle(BreeHomePalette.lightOrange)
                                Text(playbackMessage).font(.subheadline.weight(.semibold)).lineLimit(1)
                            }
                            Spacer()
                            Button(action: stopPlayback) { Image(systemName: "stop.fill").foregroundStyle(.white).padding(10).glassEffect(.regular.tint(BreeHomePalette.glassTint).interactive(), in: Circle()) }
                        }
                        .padding(14)
                        .glassEffect(.regular.tint(BreeHomePalette.glassTint), in: RoundedRectangle(cornerRadius: 18))
                    }
                    } else if selectedHomeTab == .artists {
                        if connectionResult?.isSuccess == true {
                            homepageArtistsSection
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Artists")
                                    .font(.title2.bold())
                                    .foregroundStyle(BreeHomePalette.lightOrange)
                                Text("Connect to your music library to browse artists and their albums.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.68))
                                Button { showingProfile = true } label: {
                                    Label("Connect music library", systemImage: "person.crop.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glassProminent)
                            }
                            .padding(16)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                    } else if selectedHomeTab == .albums {
                        albumsPage
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background {
                ZStack {
                    LinearGradient(
                        colors: [BreeHomePalette.surface, BreeHomePalette.surface.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 6) {
                    if currentTrackID != nil && !isSearchFieldFocused {
                        miniPlayerBar
                            .frame(maxWidth: .infinity)
                    }
                    #if os(iOS)
                    if !isSearchFieldFocused {
                        homeBottomBar
                    }
                    #endif
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background { Rectangle().fill(.clear).ignoresSafeArea(edges: .bottom) }
            }
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingEqualizer) {
                #if os(iOS)
                GraphicEqualizerView()
                #endif
            }
            .sheet(isPresented: $showingProfile) {
                profileSheet
            }
            .sheet(isPresented: $showingAlbumDetail) {
                albumDetailSheet
            }
            .sheet(isPresented: $showingArtistBrowser) {
                artistBrowserSheet
            }
            .sheet(isPresented: $showingMoodMixDetail) {
                moodMixDetailSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            #if os(iOS)
            .sheet(isPresented: $showingSettings) {
                MusicSettingsView(
                    appearanceThemeRaw: $appearanceThemeRaw,
                    streamQualityRaw: $streamQualityRaw,
                    connectionQuality: {
                        #if os(iOS)
                        switch networkPathMonitor.connection {
                        case .wifi: "Wi-Fi"
                        case .cellular: "Cellular"
                        case .constrained: "Low-data connection"
                        case .unknown: "Network type unknown"
                        }
                        #else
                        "Desktop"
                        #endif
                    }(),
                    crossfadeEnabled: Binding(
                        get: { nowPlaying.crossfadeEnabled },
                        set: { nowPlaying.setCrossfadeEnabled($0) }
                    ),
                    crossfadeDuration: Binding(
                        get: { nowPlaying.crossfadeDuration },
                        set: { nowPlaying.setCrossfadeDuration($0) }
                    ),
                    transitionCurve: Binding(
                        get: { nowPlaying.transitionCurve },
                        set: { nowPlaying.setTransitionCurve($0) }
                    ),
                    beatSyncEnabled: Binding(
                        get: { nowPlaying.beatSyncEnabled },
                        set: { nowPlaying.setBeatSyncEnabled($0) }
                    ),
                    onOpenProfile: {
                        showingSettings = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            showingProfile = true
                        }
                    },
                    onOpenEqualizer: {
                        showingSettings = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            showingEqualizer = true
                        }
                    }
                )
            }
            #endif
            #if os(iOS)
            .overlay {
                if showingNowPlaying {
                    nowPlayingScreen
                        .ignoresSafeArea()
                        .transition(.asymmetric(insertion: .identity, removal: .move(edge: .bottom)))
                        .zIndex(2)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.88), value: showingNowPlaying)
            .overlay {
                if isLocked {
                    lockScreen
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    scheduleRelock()
                    if isLoadingMoodPlaylists { beginMoodRefreshBackgroundTime() }
                } else if newPhase == .active {
                    relockTask?.cancel()
                    relockTask = nil
                    endMoodRefreshBackgroundTime()
                    refreshServerAddressOnForeground()
                }
            }
            .onChange(of: showingSettings) { _, isShowing in
                if !isShowing && selectedHomeTab == .settings {
                    selectedHomeTab = .home
                }
            }
            .onChange(of: nowPlaying.isPlaying) { _, playing in
                isPaused = !playing
            }
            #endif
            .onAppear {
                #if os(iOS)
                weatherLocation.refreshOnOpen()
                #endif
            if let data = UserDefaults.standard.data(forKey: "BreeMusic.MostPlayed"),
               let saved = try? JSONDecoder().decode([MostPlayedTrackRecord].self, from: data) {
                mostPlayed = saved
            }
            if let data = UserDefaults.standard.data(forKey: "BreeMusic.ListeningHistory"),
               let saved = try? JSONDecoder().decode([ListeningHistoryEvent].self, from: data) {
                listeningHistory = saved
            }
            if let data = UserDefaults.standard.data(forKey: "BreeMusic.RecentOpenedAlbums"),
               let saved = try? JSONDecoder().decode([RecentAlbumOpen].self, from: data) {
                recentOpenedAlbums = saved
            }
            if let data = UserDefaults.standard.data(forKey: "BreeMusic.RecentMixHistory"),
               let saved = try? JSONDecoder().decode([RecentMixPlayback].self, from: data) {
                recentMixHistory = saved
            }
            if let data = UserDefaults.standard.data(forKey: "BreeMusic.AlbumInfoCache"),
               let saved = try? JSONDecoder().decode([String: NavidromeAlbumInfo].self, from: data) {
                albumInfoCache = saved
            }
                loadLyricsSearchCache()
                #if os(iOS)
                nowPlaying.onTrackChanged = { track in
                    currentTrackID = track?.id
                    isPaused = false
                    playbackMessage = track?.title
                    if let track,
                       let album = albumByTrackID[track.id] ?? albums.first(where: { $0.name == track.album && $0.artist == track.artist }) {
                        recordPlayed(track, in: album)
                    }
                    if track != nil && openPlayerAfterTrackStarts {
                        showingNowPlaying = true
                        openPlayerAfterTrackStarts = false
                    }
                }
                #endif
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BreeMusic.Widget.Play"))) { _ in
                guard nowPlaying.title != nil else { return }
                nowPlaying.resume()
                isPaused = false
                playbackMessage = nowPlaying.title
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BreeMusic.Widget.Pause"))) { _ in
                nowPlaying.pause()
                isPaused = true
                if let title = nowPlaying.title { playbackMessage = "Paused · \(title)" }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BreeMusic.Widget.Next"))) { _ in
                Task {
                    do { try await nowPlaying.nextTrack() }
                    catch { playbackMessage = "Could not play next track: \(error.localizedDescription)" }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BreeMusic.Widget.Previous"))) { _ in
                Task {
                    do { try await nowPlaying.previousTrack() }
                    catch { playbackMessage = "Could not play previous track: \(error.localizedDescription)" }
                }
            }
            #endif
            }
        }
    }

    #if os(iOS)
    private var homeBottomBar: some View {
        HStack(spacing: 8) {
            homeTabButton(.home, title: "Home", symbol: "house.fill") {
                selectedHomeTab = .home
            }
            homeTabButton(.albums, title: "Albums", symbol: "square.stack.fill") {
                selectedHomeTab = .albums
            }
            homeTabButton(.artists, title: "Artists", symbol: "music.mic") {
                selectedHomeTab = .artists
            }
            homeTabButton(.settings, title: "Settings", symbol: "slider.horizontal.3") {
                selectedHomeTab = .settings
                showingSettings = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(.ultraThinMaterial.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        .glassEffect(.regular.tint(BreeHomePalette.glassTint.opacity(0.12)), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.045), lineWidth: 0.7)
        }
    }

    private func homeTabButton(_ tab: HomeTab, title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selectedHomeTab == tab ? BreeHomePalette.lightOrange : .white.opacity(0.68))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                if selectedHomeTab == tab {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(BreeHomePalette.glassTint.opacity(0.42))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
    #endif

    private var profileSheet: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Navidrome account", systemImage: "person.crop.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Your server address stays private in BreeMusic. Login details are stored securely on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                Button { showingRecap = true } label: {
                    Label("Listening Recap", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BreeHomePalette.lightOrange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                Group {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .textContentType(.username)
                        #endif
                    SecureField("Password", text: $password)
                        #if os(iOS)
                        .textContentType(.password)
                        #endif
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .glassEffect(.regular.tint(BreeHomePalette.glassTint), in: RoundedRectangle(cornerRadius: 14))

                Button {
                    showingProfile = false
                    connect()
                } label: {
                    HStack {
                        if isConnecting { ProgressView() }
                        Text(isConnecting ? "Connecting…" : "Save and connect")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(isConnecting || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                Spacer(minLength: 0)
            }
            .padding(24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingProfile = false }
                }
            }
        }
        .sheet(isPresented: $showingRecap) {
            ListeningRecapView(events: listeningHistory)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private var librarySearchSection: some View {
        ScrollViewReader { searchProxy in
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(BreeHomePalette.lightOrange)
                TextField("Search tracks, artists, albums", text: $searchText)
                    .focused($isSearchFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { searchLibrary() }
                    .onChange(of: searchText) { _, _ in
                        showAllSearchArtists = false
                        showAllSearchTracks = false
                        lyricSearchMatches = []
                        lyricsSearchedQuery = nil
                        lyricsSearchTask?.cancel()
                        isSearchingLyrics = false
                        searchResults = nil
                        searchLibrary(debounce: true)
                    }
                if isSearchingLibrary || isSearchingLyrics {
                    ProgressView().tint(BreeHomePalette.lightOrange)
                } else {
                    Button { searchLibrary() } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(BreeHomePalette.lightOrange)
                    }
                    .accessibilityLabel("Search library")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))

            if let searchResults, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !lyricSearchMatches.isEmpty {
                    searchResultGroup(title: "LYRIC MATCHES · \(lyricSearchMatches.count)") {
                        ForEach(lyricSearchMatches.prefix(10)) { track in
                            Button { playSearchTrack(track, results: searchResults, lyricQuery: searchText) } label: {
                                lyricSearchResultRow(track, query: searchText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !searchResults.songs.isEmpty {
                    searchResultGroup(title: "Tracks") {
                        ForEach(Array(searchResults.songs.prefix(showAllSearchTracks ? searchResults.songs.count : 10).enumerated()), id: \.element.id) { index, track in
                            Button { playSearchTrack(track, results: searchResults) } label: {
                                trackSearchResultRow(track)
                            }
                            .buttonStyle(.plain)
                            .id(index == 10 ? "search-tracks-rest" : track.id)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if searchResults.songs.count > 10 {
                            Button {
                                let shouldExpand = !showAllSearchTracks
                                withAnimation(.smooth(duration: 0.28)) {
                                    showAllSearchTracks = shouldExpand
                                }
                                if shouldExpand {
                                    Task { @MainActor in
                                        await Task.yield()
                                        withAnimation(.smooth(duration: 0.32)) {
                                            searchProxy.scrollTo("search-tracks-rest", anchor: .top)
                                        }
                                    }
                                }
                            } label: {
                                Label(
                                    showAllSearchTracks ? "Show fewer tracks" : "Show all \(searchResults.songs.count) tracks",
                                    systemImage: showAllSearchTracks ? "chevron.up" : "chevron.down"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BreeHomePalette.lightOrange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !searchResults.artists.isEmpty {
                    searchResultGroup(title: "Artists") {
                        ForEach(Array(searchResults.artists.prefix(showAllSearchArtists ? searchResults.artists.count : 5).enumerated()), id: \.element.id) { index, artist in
                            Button { showArtist(artist.name) } label: {
                                artistSearchRow(artist.name)
                            }
                            .buttonStyle(.plain)
                            .id(index == 5 ? "search-artists-rest" : artist.id)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if searchResults.artists.count > 5 {
                            Button {
                                let shouldExpand = !showAllSearchArtists
                                withAnimation(.smooth(duration: 0.28)) {
                                    showAllSearchArtists = shouldExpand
                                }
                                if shouldExpand {
                                    Task { @MainActor in
                                        await Task.yield()
                                        withAnimation(.smooth(duration: 0.32)) {
                                            searchProxy.scrollTo("search-artists-rest", anchor: .top)
                                        }
                                    }
                                }
                            } label: {
                                Label(
                                    showAllSearchArtists ? "Show fewer artists" : "Show all \(searchResults.artists.count) artists",
                                    systemImage: showAllSearchArtists ? "chevron.up" : "chevron.down"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BreeHomePalette.lightOrange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !searchResults.albums.isEmpty {
                    searchResultGroup(title: "Albums") {
                        ForEach(searchResults.albums) { album in
                            Button { openAlbum(album) } label: {
                                HStack(spacing: 10) {
                                    albumTile(album, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(album.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        let albumDetails = [album.artist, album.year.map(String.init), album.songCount.map { "\($0) tracks" }].compactMap { $0 }
                                        Text(albumDetails.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.62))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        }
    }

    private var recapCard: some View {
        Button { showingRecap = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(BreeHomePalette.lightOrange)
                    .frame(width: 48, height: 48)
                    .background(BreeHomePalette.burntOrange.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your BreeMusic Recap").font(.headline).foregroundStyle(.white)
                    Text("Listening highlights, favorite artists and most-played tracks")
                        .font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.white.opacity(0.55))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(BreeHomePalette.glassTint), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var moodPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Listening Mixes")
                    .font(.title3.bold())
                    .foregroundStyle(BreeHomePalette.lightOrange)
                if isLoadingMoodPlaylists && moodPlaylistsLoaded {
                    ProgressView().controlSize(.mini).tint(BreeHomePalette.lightOrange)
                    Text("Updating \(moodAlbumsProcessed)/\(moodAlbumsTotal)")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if isLoadingMoodPlaylists && !moodPlaylistsLoaded {
                HStack(spacing: 10) {
                    ProgressView().tint(BreeHomePalette.lightOrange)
                    Text(moodAlbumsTotal > 0
                         ? "Preparing listening mixes · \(moodAlbumsProcessed)/\(moodAlbumsTotal) albums"
                         : "Preparing listening mixes…")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if moodPlaylistsLoaded && !moodPlaylists.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(moodMixNames, id: \.self) { mixName in
                        let songs = moodPlaylists[mixName] ?? []
                        homepageCategoryCard(
                            title: mixName,
                            description: moodMixDescription(mixName),
                            symbol: moodMixSymbol(mixName),
                            accent: moodMixAccent(mixName),
                            isActive: activeMoodMix == mixName,
                            hasTracks: !songs.isEmpty,
                            openAction: { openMoodMix(mixName) },
                            playAction: { toggleMoodMix(mixName) }
                        )
                    }
                }
            } else if moodPlaylistsLoaded {
                Text("Listening mixes will appear when tracks are available in your library.")
                    .font(.caption).foregroundStyle(.white.opacity(0.62))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 2)
    }

    private func homepageCategoryCard(
        title: String,
        description: String,
        symbol: String,
        accent: Color,
        isActive: Bool,
        hasTracks: Bool,
        openAction: @escaping () -> Void,
        playAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 7) {
            Button(action: openAction) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(LinearGradient(colors: [accent.opacity(0.78), accent.opacity(0.32)], startPoint: .bottomLeading, endPoint: .topTrailing))
                        Image(systemName: symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(description)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show tracks in \(title)")

            Button(action: playAction) {
                Image(systemName: isActive ? "stop.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle()
                            .fill(isActive ? accent.opacity(0.72) : .white.opacity(0.10))
                            .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.8))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!hasTracks)
            .opacity(hasTracks ? 1 : 0.38)
            .accessibilityLabel(isActive ? "Stop \(title)" : "Play \(title)")
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isActive ? accent.opacity(0.58) : .white.opacity(0.07), lineWidth: 1)
        }
    }

    private var moodMixNames: [String] {
        [
            "Morning Coffee & Ease-In",
            "Deep Work & Coding Focus",
            "Midday Energy & Feel-Good Boost",
            "High-Intensity & Running",
            "Cooking & Hosting Dinner",
            "Daytime Road Trip & Cruising",
            "Late-Night Drive",
            "Gaming & Immersive Sessions",
            "Evening Unwind & Lounge",
            "Sleep & Deep Relaxation"
        ]
    }

    private func moodMixDescription(_ mix: String) -> String {
        switch mix {
        case "Morning Coffee & Ease-In": "Warm acoustic, gentle instrumentals, light indie, and slow starts."
        case "Deep Work & Coding Focus": "Lo-fi and ambient instrumentals with steady rhythms and few vocals."
        case "Midday Energy & Feel-Good Boost": "Bright pop and funk with upbeat feel-good energy around 110–125 BPM."
        case "High-Intensity & Running": "Fast, high-energy EDM and hip-hop with heavy bass, usually 130+ BPM."
        case "Cooking & Hosting Dinner": "Groovy, warm neo-soul and bossa nova for laid-back dinner hosting."
        case "Daytime Road Trip & Cruising": "Classic and indie rock, sing-along hooks, and dynamic upbeat drive."
        case "Late-Night Drive": "Moody alternative R&B and deep house with atmospheric, bass-led sound."
        case "Gaming & Immersive Sessions": "Immersive instrumental synthwave, future garage, and cinematic electronic."
        case "Evening Unwind & Lounge": "Chillhop, smooth jazz, and downtempo lounge for winding down."
        default: "Solo piano and calm, minimalist ambient music with very slow or no beats."
        }
    }

    private func moodMixSymbol(_ mix: String) -> String {
        switch mix {
        case "Morning Coffee & Ease-In": "cup.and.saucer.fill"
        case "Deep Work & Coding Focus": "laptopcomputer"
        case "Midday Energy & Feel-Good Boost": "sun.max.fill"
        case "High-Intensity & Running": "figure.run"
        case "Cooking & Hosting Dinner": "fork.knife"
        case "Daytime Road Trip & Cruising": "car.side.fill"
        case "Late-Night Drive": "moon.stars.fill"
        case "Gaming & Immersive Sessions": "gamecontroller.fill"
        case "Evening Unwind & Lounge": "sofa.fill"
        default: "moon.zzz.fill"
        }
    }

    private func moodMixAccent(_ mix: String) -> Color {
        switch mix {
        case "Morning Coffee & Ease-In": Color(red: 0.84, green: 0.62, blue: 0.38)
        case "Deep Work & Coding Focus": Color(red: 0.42, green: 0.68, blue: 0.82)
        case "Midday Energy & Feel-Good Boost": Color(red: 1.0, green: 0.69, blue: 0.28)
        case "High-Intensity & Running": Color(red: 0.95, green: 0.34, blue: 0.27)
        case "Cooking & Hosting Dinner": Color(red: 0.77, green: 0.48, blue: 0.38)
        case "Daytime Road Trip & Cruising": Color(red: 0.38, green: 0.72, blue: 0.78)
        case "Late-Night Drive": Color(red: 0.48, green: 0.44, blue: 0.76)
        case "Gaming & Immersive Sessions": Color(red: 0.59, green: 0.45, blue: 0.92)
        case "Evening Unwind & Lounge": Color(red: 0.45, green: 0.68, blue: 0.57)
        default: Color(red: 0.45, green: 0.55, blue: 0.72)
        }
    }

    private func openMoodMix(_ mix: String) {
        selectedMoodMixName = mix
        showingMoodMixDetail = true
    }

    private func toggleMoodMix(_ mix: String) {
        if activeMoodMix == mix {
            stopPlayback()
        } else {
            playMoodPlaylist(mix)
        }
    }

    private var moodMixDetailSheet: some View {
        NavigationStack {
            Group {
                if let mix = selectedMoodMixName {
                    let songs = moodPlaylists[mix] ?? []
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(moodMixDescription(mix))
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.76))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    toggleMoodMix(mix)
                                } label: {
                                    Label(activeMoodMix == mix ? "Stop Mix" : "Play Mix", systemImage: activeMoodMix == mix ? "stop.fill" : "play.fill")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glassProminent)
                                .disabled(songs.isEmpty)
                            }
                            .padding(.vertical, 5)
                            .listRowBackground(Color.clear)
                        }
                        Section("Tracks · \(songs.count)") {
                            if songs.isEmpty {
                                Text("No matching tracks are available in your library yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(songs.enumerated()), id: \.element.id) { index, track in
                                    let album = albumByTrackID[track.id] ?? NavidromeAlbum(
                                        id: track.albumId ?? track.id,
                                        name: track.album ?? "Unknown album",
                                        artist: track.artist,
                                        year: track.year,
                                        songCount: nil,
                                        coverArt: track.coverArt
                                    )
                                    Button {
                                        playMoodPlaylist(mix, startingWith: track.id)
                                        showingMoodMixDetail = false
                                    } label: {
                                        HStack(spacing: 10) {
                                            Text(String(format: "%02d", index + 1))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                                .frame(width: 25, alignment: .leading)
                                            albumTile(album, size: 44)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                                Text(track.artist ?? album.artist ?? album.name)
                                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Spacer(minLength: 4)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(BreeHomePalette.surface)
                    .navigationTitle(mix)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingMoodMixDetail = false }
                        }
                    }
                } else {
                    ContentUnavailableView("Choose a listening mix", systemImage: "music.note.list")
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var breeRadioSection: some View {
        Button(action: startLibraryRadio) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [BreeHomePalette.lightOrange.opacity(0.8), BreeHomePalette.burntOrange.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 54, height: 54)
                    Circle().stroke(.white.opacity(0.2), lineWidth: 1).frame(width: 54, height: 54)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(isStartingRadio ? "Tuning in…" : "BreeMusic Radio")
                            .font(.headline.weight(.semibold)).foregroundStyle(.white)
                        Circle().fill(BreeHomePalette.lightOrange).frame(width: 5, height: 5)
                        Text("MIX")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(BreeHomePalette.lightOrange)
                    }
                    Text("A fresh shuffle from your music")
                        .font(.caption).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if isStartingRadio { ProgressView().tint(BreeHomePalette.lightOrange) }
                else { Image(systemName: "play.fill").font(.subheadline.bold()).foregroundStyle(BreeHomePalette.lightOrange) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [BreeHomePalette.glassTint.opacity(0.24), .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(isStartingRadio)
        .accessibilityLabel("Play BreeMusic Radio from your Navidrome library")
    }

    private var homepageArtistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Artists")
                .font(.title3.bold())
                .foregroundStyle(BreeHomePalette.lightOrange)
                .frame(maxWidth: .infinity, alignment: .center)
            if !genrePlaylists.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        artistGenreChip("All", selected: selectedArtistGenre == nil) {
                            selectedArtistGenre = nil
                        }
                        ForEach(genrePlaylists.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { genre in
                            artistGenreChip(genre, selected: selectedArtistGenre == genre) {
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    selectedArtistGenre = genre
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
            }
            ForEach(Array(displayedHomepageArtistNames.enumerated()), id: \.offset) { entry in
                let artistIndex = entry.offset
                let artist = entry.element
                let artistAlbums = albums.filter { $0.artist?.localizedCaseInsensitiveCompare(artist) == .orderedSame }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                let media = recentMedia(for: artist, fallbackAlbums: artistAlbums)
                VStack(alignment: .leading, spacing: 8) {
                    Button { showArtist(artist) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "person.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.9))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(artist)
                                    .font(.title3.weight(.bold))
                                    .tracking(0.15)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(artistHeaderGradient(index: artistIndex))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
                                }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(artist) artist window")
                    .padding(.top, 9)

                    if !media.isEmpty {
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 11) {
                                ForEach(media.prefix(10)) { item in
                                    Button {
                                        if let album = item.album {
                                            openAlbum(album)
                                        } else if let track = item.track {
                                            playFromHistory(track)
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            if let album = item.album {
                                                albumTile(album, size: 104)
                                            } else if let track = item.track {
                                                albumTile(track.album, size: 104)
                                            }
                                            Text(item.title)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(2)
                                                .frame(width: 104, alignment: .leading)
                                            Text(item.album != nil ? "ALBUM" : "TRACK")
                                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                                                .tracking(1.1)
                                                .foregroundStyle(BreeHomePalette.slateLabel)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    } else {
                        Text("No albums in this library")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Rectangle().fill(BreeHomePalette.separator).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private var albumsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Albums")
                .font(.title2.bold())
                .foregroundStyle(BreeHomePalette.lightOrange)
                .frame(maxWidth: .infinity, alignment: .center)

            if connectionResult?.isSuccess == true {
                if displayedAlbums.isEmpty {
                    ContentUnavailableView("No albums yet", systemImage: "square.stack", description: Text("Your music library has no albums to show."))
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 18) {
                        ForEach(displayedAlbums) { album in
                            Button { openAlbum(album) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    albumTile(album, size: 150)
                                        .frame(maxWidth: .infinity)
                                    Text(album.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                                    Text(album.artist ?? "Unknown artist")
                                        .font(.caption)
                                        .foregroundStyle(BreeHomePalette.slateLabel)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(9)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
                                .contentShape(RoundedRectangle(cornerRadius: 15))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect to your music library to browse albums.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                    Button { showingProfile = true } label: {
                        Label("Connect music library", systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(.horizontal, 2)
    }

    private var homepageArtistNames: [String] {
        if selectedHomeTab == .artists { return artistNames }
        var names: [String] = []
        for name in recentSearchedArtists + randomHomepageArtists + artistNames {
            guard !names.contains(where: { artistCacheKey($0) == artistCacheKey(name) }) else { continue }
            names.append(name)
            if names.count == 10 { break }
        }
        return names
    }

    private var displayedHomepageArtistNames: [String] {
        guard let selectedArtistGenre else { return homepageArtistNames }
        var names: [String] = []
        for track in genrePlaylists[selectedArtistGenre] ?? [] {
            let name = albumByTrackID[track.id]?.artist
                ?? albums.first(where: { $0.id == (track.albumId ?? "") })?.artist
                ?? track.displayAlbumArtist
                ?? track.albumArtists?.first?.name
                ?? track.artist
            guard let name, !name.isEmpty,
                  !names.contains(where: { artistCacheKey($0) == artistCacheKey(name) }) else { continue }
            names.append(name)
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func artistGenreChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : BreeHomePalette.slateLabel)
                .shadow(color: selected ? .clear : .white.opacity(0.14), radius: 0.6, x: 0, y: -0.5)
                .shadow(color: selected ? .clear : .black.opacity(0.9), radius: 1, x: 0, y: 1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule().fill(BreeHomePalette.burntOrange.opacity(0.24))
                    }
                }
                .overlay {
                    if selected {
                        Capsule().strokeBorder(BreeHomePalette.lightOrange.opacity(0.9), lineWidth: 1.2)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func artistHeaderGradient(index: Int) -> LinearGradient {
        let hues: [Color] = [
            Color(red: 0.76, green: 0.31, blue: 0.12),
            Color(red: 0.55, green: 0.27, blue: 0.42),
            Color(red: 0.28, green: 0.34, blue: 0.62),
            Color(red: 0.16, green: 0.46, blue: 0.53),
            Color(red: 0.39, green: 0.43, blue: 0.32)
        ]
        let start = index % hues.count
        let end = (start + 1) % hues.count
        return LinearGradient(
            colors: [hues[start].opacity(0.72), hues[end].opacity(0.46), BreeHomePalette.glassTint.opacity(0.3)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func recentMedia(for artist: String, fallbackAlbums: [NavidromeAlbum]) -> [ArtistRecentMedia] {
        var media: [ArtistRecentMedia] = []
        var seenTrackIDs = Set<String>()
        for event in listeningHistory.sorted(by: { $0.date > $1.date }) {
            guard let record = mostPlayed.first(where: { item in
                if let trackID = event.trackID { return item.track.id == trackID }
                return item.track.title == event.trackTitle
                    && (item.track.artist ?? "Unknown artist") == event.artist
                    && item.album.name == event.album
            }),
            (record.track.artist ?? record.album.artist ?? "").localizedCaseInsensitiveCompare(artist) == .orderedSame,
            seenTrackIDs.insert(record.track.id).inserted else { continue }
            media.append(ArtistRecentMedia(id: "track-\(record.track.id)", title: record.track.title, date: event.date, album: nil, track: record))
        }

        var seenAlbumIDs = Set<String>()
        for openedAlbum in recentOpenedAlbums.sorted(by: { $0.date > $1.date }) {
            guard openedAlbum.album.artist?.localizedCaseInsensitiveCompare(artist) == .orderedSame,
                  seenAlbumIDs.insert(openedAlbum.album.id).inserted else { continue }
            media.append(ArtistRecentMedia(id: "album-\(openedAlbum.album.id)", title: openedAlbum.album.name, date: openedAlbum.date, album: openedAlbum.album, track: nil))
        }

        if media.isEmpty {
            media = fallbackAlbums.map {
                ArtistRecentMedia(id: "album-\($0.id)", title: $0.name, date: .distantPast, album: $0, track: nil)
            }
        }
        return Array(media.sorted { $0.date > $1.date }.prefix(10))
    }

    private func searchResultGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .tracking(1.1)
                .foregroundStyle(BreeHomePalette.lightOrange)
                .padding(.horizontal, 4)
            content()
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func searchResultRow(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(BreeHomePalette.lightOrange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.white).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func lyricSearchResultRow(_ track: NavidromeTrack, query: String) -> some View {
        let base = trackSearchResultRow(track)
        let excerpt = lyricSnippet(for: track, query: query) ?? ""
        return VStack(alignment: .leading, spacing: 3) {
            base
            if !excerpt.isEmpty {
                Text("“\(excerpt)”")
                    .font(.caption)
                    .foregroundStyle(BreeHomePalette.lightOrange.opacity(0.92))
                    .lineLimit(2)
                    .padding(.leading, 54)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func lyricSnippet(for track: NavidromeTrack, query: String) -> String? {
        guard let lyrics = lyricTextCache[track.id],
              let match = lyrics.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let startDistance = lyrics.distance(from: lyrics.startIndex, to: match.lowerBound)
        let endDistance = lyrics.distance(from: lyrics.startIndex, to: match.upperBound)
        let startOffset = max(0, startDistance - 46)
        let endOffset = min(lyrics.count, endDistance + 54)
        guard let start = lyrics.index(lyrics.startIndex, offsetBy: startOffset, limitedBy: lyrics.endIndex),
              let end = lyrics.index(lyrics.startIndex, offsetBy: endOffset, limitedBy: lyrics.endIndex) else { return nil }
        let body = String(lyrics[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        let leading = startOffset > 0 ? "…" : ""
        let trailing = endOffset < lyrics.count ? "…" : ""
        return leading + body + trailing
    }

    private func trackSearchResultRow(_ track: NavidromeTrack) -> some View {
        let album = albums.first(where: { $0.id == track.albumId })
            ?? albums.first(where: { $0.name == track.album && $0.artist == track.artist })
            ?? NavidromeAlbum(
                id: track.albumId ?? track.id,
                name: track.album ?? "Unknown album",
                artist: track.artist,
                year: track.year,
                songCount: nil,
                coverArt: track.coverArt
            )
        return HStack(spacing: 10) {
            albumTile(album, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.subheadline.weight(.medium)).foregroundStyle(.white).lineLimit(1)
                Text(track.displayArtist ?? track.artist ?? "Unknown artist")
                    .font(.caption).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.45))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func artistSearchRow(_ artist: String) -> some View {
        HStack(spacing: 10) {
            if let imageURL = artistInfoCache[artistCacheKey(artist)]?.preferredImageURL(serverAddress: serverAddress) {
                CachedArtworkView(url: imageURL) { artistSearchPlaceholder(artist) }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                artistSearchPlaceholder(artist)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            Text(artist)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func artistSearchPlaceholder(_ artist: String) -> some View {
        ZStack {
            LinearGradient(colors: [BreeHomePalette.lightOrange, BreeHomePalette.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(artist.prefix(1).uppercased())
                .font(.title3.bold())
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var lyricsCacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BreeMusicLyricsIndex.json")
    }

    private func loadLyricsSearchCache() {
        guard let url = lyricsCacheFileURL,
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(BreeLyricsSearchCache.self, from: data) else { return }
        lyricTextCache = cache.lyrics
        lyricsKeywordIndex = cache.keywordTrackIDs
        if lyricsKeywordIndex.isEmpty {
            for (trackID, lyrics) in lyricTextCache { indexLyrics(lyrics, for: trackID) }
        }
    }

    private func saveLyricsSearchCache() {
        guard let url = lyricsCacheFileURL,
              let data = try? JSONEncoder().encode(BreeLyricsSearchCache(lyrics: lyricTextCache, keywordTrackIDs: lyricsKeywordIndex)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func indexLyrics(_ lyrics: String, for trackID: String) {
        for word in lyrics.lowercased()
            .folding(options: [.diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter({ $0.count > 1 }) {
            lyricsKeywordIndex[word, default: []].insert(trackID)
        }
    }

    private func lyricSearchCandidateIDs(for query: String) -> Set<String>? {
        let words = query.lowercased()
            .folding(options: [.diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter({ $0.count > 1 })
        guard !words.isEmpty else { return nil }
        var sets: [Set<String>] = []
        for word in words {
            guard let trackIDs = lyricsKeywordIndex[word] else { return [] }
            sets.append(trackIDs)
        }
        return sets.dropFirst().reduce(sets.first ?? []) { $0.intersection($1) }
    }

    private func searchLyricsForQuery(_ requestedQuery: String? = nil) {
        let query = requestedQuery ?? searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        lyricsSearchTask?.cancel()
        isSearchingLyrics = true
        lyricSearchMatches = []
        lyricsSearchedQuery = nil
        lyricsSearchTask = Task {
            defer {
                if !Task.isCancelled && searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query {
                    isSearchingLyrics = false
                }
            }
            do {
                var candidates: [NavidromeTrack] = []
                for album in albums {
                    try Task.checkCancellation()
                    candidates.append(contentsOf: try await NavidromeConnection.loadTracks(
                        address: serverAddress,
                        username: username,
                        password: password,
                        albumID: album.id
                    ))
                }
                var unique: [String: NavidromeTrack] = [:]
                for track in candidates { unique[track.id] = track }
                let tracksToCheck = Array(unique.values)
                let indexedIDs = lyricSearchCandidateIDs(for: query)
                var matches = tracksToCheck.filter { track in
                    if let indexedIDs, !indexedIDs.contains(track.id) { return false }
                    return (lyricTextCache[track.id] ?? "").localizedCaseInsensitiveContains(query)
                }
                lyricSearchMatches = matches.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                let batchSize = 5
                for batchStart in stride(from: 0, to: tracksToCheck.count, by: batchSize) {
                    try Task.checkCancellation()
                    let batch = Array(tracksToCheck[batchStart..<min(batchStart + batchSize, tracksToCheck.count)])
                    let cachedLyrics = lyricTextCache
                    let checked = await withTaskGroup(of: (NavidromeTrack, String).self, returning: [(NavidromeTrack, String)].self) { group in
                        for track in batch {
                            group.addTask {
                                if let cached = cachedLyrics[track.id] { return (track, cached) }
                                let lines = (try? await NavidromeConnection.loadLyrics(
                                    address: serverAddress,
                                    username: username,
                                    password: password,
                                    trackID: track.id,
                                    artist: track.artist ?? "",
                                    title: track.title
                                )) ?? []
                                return (track, lines.map(\.text).joined(separator: "\n"))
                            }
                        }
                        var values: [(NavidromeTrack, String)] = []
                        for await value in group { values.append(value) }
                        return values
                    }
                    for (track, text) in checked {
                        lyricTextCache[track.id] = text
                        indexLyrics(text, for: track.id)
                        if text.localizedCaseInsensitiveContains(query), !matches.contains(where: { $0.id == track.id }) {
                            matches.append(track)
                        }
                    }
                    guard !Task.isCancelled,
                          searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                    lyricSearchMatches = matches.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                }
                guard !Task.isCancelled,
                      searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                lyricSearchMatches = matches.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                lyricsSearchedQuery = query
                saveLyricsSearchCache()
            } catch is CancellationError {
                return
            } catch {
                guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                lyricsSearchedQuery = query
            }
        }
    }

    private func searchLibrary(debounce: Bool = false) {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            isSearchingLibrary = false
            return
        }

        isSearchingLibrary = true
        searchTask = Task {
            defer {
                if !Task.isCancelled && searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query {
                    isSearchingLibrary = false
                }
            }
            if debounce {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            do {
                let results = try await NavidromeConnection.search(address: serverAddress, username: username, password: password, query: query)
                guard !Task.isCancelled,
                      searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                searchResults = results
                searchLyricsForQuery(query)
            } catch {
                guard !Task.isCancelled,
                      searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                let emptyResults = NavidromeSearchResults(songs: [], albums: [], artists: [])
                searchResults = emptyResults
                searchLyricsForQuery(query)
            }
        }
    }

    private func playSearchTrack(_ searchedTrack: NavidromeTrack, results: NavidromeSearchResults, lyricQuery: String? = nil) {
        guard let albumID = searchedTrack.albumId else {
            playbackMessage = "Could not find this track’s album in the library."
            return
        }
        let album = albums.first(where: { $0.id == albumID })
            ?? results.albums.first(where: { $0.id == albumID })
            ?? NavidromeAlbum(id: albumID, name: searchedTrack.album ?? "Unknown album", artist: searchedTrack.artist, year: searchedTrack.year, songCount: nil, coverArt: searchedTrack.coverArt)
        selectedAlbum = album
        isLoadingTracks = true
        Task {
            defer { if selectedAlbum?.id == album.id { isLoadingTracks = false } }
            do {
                let loaded = try await NavidromeConnection.loadTracks(address: serverAddress, username: username, password: password, albumID: album.id)
                guard selectedAlbum?.id == album.id else { return }
                tracks = loaded
                for track in loaded { albumByTrackID[track.id] = album }
                guard let track = loaded.first(where: { $0.id == searchedTrack.id }) else {
                    playbackMessage = "That track is no longer in the album."
                    return
                }
                if let lyricQuery {
                    isSearchFieldFocused = false
                    pendingLyricsSearch = PendingLyricsSearch(trackID: track.id, query: lyricQuery)
                    lyricSearchTargetLineID = nil
                    showingLyrics = true
                    if currentTrackID == track.id {
                        showingNowPlaying = true
                    } else {
                        play(track, opensNowPlaying: true)
                    }
                } else {
                    play(track, opensNowPlaying: false)
                }
            } catch {
                playbackMessage = "Could not load the track: \(error.localizedDescription)"
            }
        }
    }

    private var albumDetailSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let album = selectedAlbum {
                        if let coverArt = album.coverArt,
                           let url = try? NavidromeConnection.coverArtURL(address: serverAddress, username: username, password: password, artworkID: coverArt, size: 512) {
                            CachedArtworkView(url: url) { albumPlaceholder }
                                .frame(maxWidth: 300)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 28))
                                .frame(maxWidth: .infinity)
                        } else {
                            albumPlaceholder
                                .frame(maxWidth: 300)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 28))
                                .frame(maxWidth: .infinity)
                        }
                        Text(album.name)
                            .font(.largeTitle.bold())
                        if let artist = album.artist, !artist.isEmpty {
                            Button { showArtist(artist) } label: {
                                Label(artist, systemImage: "person")
                                    .font(.title3.weight(.medium))
                            }
                            .buttonStyle(.glass)
                        }
                        Text([album.year.map(String.init), album.songCount.map { "\($0) tracks" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))

                        if let audioSummary = albumAudioSummary(tracks) {
                            Label(audioSummary, systemImage: "waveform")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        albumInformationSection

                        if isLoadingTracks {
                            ProgressView("Loading album tracks…")
                                .frame(maxWidth: .infinity)
                                .padding(24)
                        } else if let trackLoadError {
                            Text(trackLoadError)
                                .foregroundStyle(.red)
                                .padding(14)
                        } else {
                            ForEach(tracks) { track in
                                Button { play(track, opensNowPlaying: false) } label: {
                                    HStack(spacing: 12) {
                                        Text(track.track.map { String($0) } ?? "•")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.55))
                                            .frame(width: 28)
                                        Text(track.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Spacer(minLength: 8)
                                        if let duration = track.duration {
                                            Text(Self.durationLabel(duration))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                        Image(systemName: currentTrackID == track.id && !isPaused ? "pause.fill" : "play.fill")
                                            .foregroundStyle(BreeHomePalette.lightOrange)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .contentShape(Rectangle())
                                    .glassEffect(.regular.tint(BreeHomePalette.glassTint).interactive(), in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, currentTrackID == nil ? 8 : 88)
            }
            .task(id: selectedAlbum?.id) {
                await loadSelectedAlbumInfo()
            }
            .navigationTitle("Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingAlbumDetail = false }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if currentTrackID != nil && !isSearchFieldFocused {
                miniPlayerBar
                    .frame(maxWidth: 700)
                    .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var albumInformationSection: some View {
        if isLoadingAlbumInfo {
            ProgressView("Loading album information…")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else if let info = selectedAlbumInfo {
            let notes = info.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !notes.isEmpty || info.musicBrainzId != nil || info.lastFmUrl != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("About this album")
                        .font(.headline)
                    if !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let musicBrainzID = info.musicBrainzId, !musicBrainzID.isEmpty {
                        Label("MusicBrainz ID · \(musicBrainzID)", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                            .textSelection(.enabled)
                    }
                    if let lastFMURL = info.lastFmURL, let url = URL(string: lastFMURL), url.scheme == "https" {
                        Link(destination: url) {
                            Label("More album information", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(BreeHomePalette.lightOrange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func albumAudioSummary(_ albumTracks: [NavidromeTrack]) -> String? {
        guard !albumTracks.isEmpty else { return nil }
        let formats = Set(albumTracks.compactMap { track -> String? in
            if let suffix = track.suffix?.trimmingCharacters(in: .whitespacesAndNewlines), !suffix.isEmpty {
                return suffix.uppercased()
            }
            guard let contentType = track.contentType,
                  let fileType = contentType.split(separator: "/").last else { return nil }
            return String(fileType).uppercased()
        })
        let profiles = Set(albumTracks.compactMap { track -> String? in
            guard let rate = track.samplingRate, let depth = track.bitDepth else { return nil }
            let rateLabel = rate >= 1_000 ? String(format: "%.1f kHz", Double(rate) / 1_000) : "\(rate) Hz"
            let quality: String
            if rate == 44_100 && depth == 16 {
                quality = "CD quality"
            } else if rate > 44_100 || depth > 16 {
                quality = "Hi-Res"
            } else {
                quality = "Standard resolution"
            }
            return "\(quality) · \(rateLabel)/\(depth)-bit"
        })
        let pieces = [formats.sorted().joined(separator: "/"), profiles.sorted().joined(separator: " · ")]
            .filter { !$0.isEmpty }
        return pieces.isEmpty ? "Audio details unavailable" : pieces.joined(separator: " · ")
    }

    private var artistBrowserSheet: some View {
        NavigationStack {
            List {
                if let selectedArtistName {
                    Section("\(selectedArtistName) albums") {
                        artistHeader(for: selectedArtistName)
                        ForEach(albums.filter { $0.artist?.localizedCaseInsensitiveCompare(selectedArtistName) == .orderedSame }) { album in
                            VStack(alignment: .leading, spacing: 10) {
                                Button { toggleArtistAlbum(album) } label: {
                                    HStack(spacing: 12) {
                                        albumTile(album)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(album.name)
                                                .font(.headline)
                                                .foregroundStyle(.white)
                                            Text([album.year.map(String.init), album.songCount.map { "\($0) tracks" }].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.62))
                                        }
                                        Spacer()
                                        Image(systemName: expandedArtistAlbumID == album.id ? "chevron.down" : "chevron.right")
                                            .foregroundStyle(BreeHomePalette.lightOrange)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if expandedArtistAlbumID == album.id {
                                    artistAlbumTracks(album)
                                        .transition(.opacity)
                                }
                            }
                            .padding(.vertical, 7)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                } else {
                    Section("Artists") {
                        ForEach(artistNames, id: \.self) { artist in
                            Button {
                                selectedArtistName = artist
                            } label: {
                                Label(artist, systemImage: "person.crop.circle")
                                    .foregroundStyle(.white)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BreeHomePalette.surface)
            .navigationTitle(selectedArtistName ?? "Artists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedArtistName != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Artists") { selectedArtistName = nil }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingArtistBrowser = false }
                }
            }
            .task(id: selectedArtistName) {
                await loadSelectedArtistInfo()
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if currentTrackID != nil && !isSearchFieldFocused {
                miniPlayerBar
                    .frame(maxWidth: 700)
                    .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func artistHeader(for artist: String) -> some View {
        let albumImageURL = artistAlbumArtworkURL(for: artist)
        VStack(alignment: .leading, spacing: 12) {
            if let imageURL = selectedArtistInfo?.preferredImageURL(serverAddress: serverAddress) {
                CachedArtworkView(url: imageURL) {
                    if let albumImageURL {
                        CachedArtworkView(url: albumImageURL) { artistImageFallback(for: artist) }
                    } else {
                        artistImageFallback(for: artist)
                    }
                }
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            } else if let albumImageURL {
                CachedArtworkView(url: albumImageURL) {
                    artistImageFallback(for: artist)
                }
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            } else {
                artistImageFallback(for: artist)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
            }
            Text(artist)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            if let biography = selectedArtistInfo?.biography?.trimmingCharacters(in: .whitespacesAndNewlines), !biography.isEmpty {
                Text(biography)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(5)
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }

    private func artistAlbumArtworkURL(for artist: String) -> URL? {
        guard let album = albums.first(where: {
            $0.artist?.localizedCaseInsensitiveCompare(artist) == .orderedSame && $0.coverArt != nil
        }), let coverArt = album.coverArt else { return nil }
        return try? NavidromeConnection.coverArtURL(
            address: serverAddress,
            username: username,
            password: password,
            artworkID: coverArt,
            size: 512
        )
    }

    private func artistImageFallback(for artist: String) -> some View {
        ZStack {
            LinearGradient(colors: [BreeHomePalette.burntOrange.opacity(0.9), BreeHomePalette.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.mic")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
            Text(artist.prefix(1).uppercased())
                .font(.system(size: 90, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.14))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    @MainActor
    private func loadSelectedArtistInfo() async {
        guard let artist = selectedArtistName else {
            selectedArtistInfo = nil
            return
        }
        let key = artistCacheKey(artist)
        if let cached = artistInfoCache[key] {
            selectedArtistInfo = cached
            return
        }
        selectedArtistInfo = nil
        do {
            let info = try await NavidromeConnection.loadArtistInfo(
                address: serverAddress,
                username: username,
                password: password,
                artist: artist
            )
            guard selectedArtistName?.localizedCaseInsensitiveCompare(artist) == .orderedSame else { return }
            selectedArtistInfo = info
            if let info { artistInfoCache[key] = info }
        } catch {
            // Artist artwork is optional; the artist page keeps a local fallback when unavailable.
        }
    }

    @MainActor
    private func loadSelectedAlbumInfo() async {
        guard showingAlbumDetail, let album = selectedAlbum else {
            selectedAlbumInfo = nil
            return
        }
        if let cached = albumInfoCache[album.id] {
            selectedAlbumInfo = cached
            return
        }

        selectedAlbumInfo = nil
        isLoadingAlbumInfo = true
        defer { isLoadingAlbumInfo = false }
        do {
            let info = try await NavidromeConnection.loadAlbumInfo(
                address: serverAddress,
                username: username,
                password: password,
                albumID: album.id
            )
            guard showingAlbumDetail, selectedAlbum?.id == album.id else { return }
            selectedAlbumInfo = info
            if let info { albumInfoCache[album.id] = info }
        } catch {
            // Album notes and external metadata are optional; the local album tags remain visible.
        }
    }

    private func preloadAlbumInformation(for libraryAlbums: [NavidromeAlbum]) {
        let pendingAlbums = libraryAlbums.filter { albumInfoCache[$0.id] == nil }
        guard !pendingAlbums.isEmpty else { return }
        let address = serverAddress
        let accountName = username
        let accountPassword = password

        Task { @MainActor in
            await withTaskGroup(of: (String, NavidromeAlbumInfo?).self) { group in
                var nextAlbumIndex = 0
                let initialBatchCount = min(4, pendingAlbums.count)
                for _ in 0..<initialBatchCount {
                    let album = pendingAlbums[nextAlbumIndex]
                    nextAlbumIndex += 1
                    group.addTask {
                        let info = try? await NavidromeConnection.loadAlbumInfo(
                            address: address,
                            username: accountName,
                            password: accountPassword,
                            albumID: album.id
                        )
                        return (album.id, info ?? nil)
                    }
                }

                while let (albumID, info) = await group.next() {
                    if let info {
                        albumInfoCache[albumID] = info
                        if let data = try? JSONEncoder().encode(albumInfoCache) {
                            UserDefaults.standard.set(data, forKey: "BreeMusic.AlbumInfoCache")
                        }
                    }
                    if nextAlbumIndex < pendingAlbums.count {
                        let album = pendingAlbums[nextAlbumIndex]
                        nextAlbumIndex += 1
                        group.addTask {
                            let info = try? await NavidromeConnection.loadAlbumInfo(
                                address: address,
                                username: accountName,
                                password: accountPassword,
                                albumID: album.id
                            )
                            return (album.id, info ?? nil)
                        }
                    }
                }
            }
        }
    }

    private func preloadArtistInformation(for libraryAlbums: [NavidromeAlbum]) {
        let prioritizedArtists = Dictionary(grouping: libraryAlbums.compactMap { $0.artist?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }, by: artistCacheKey)
            .sorted { $0.value.count > $1.value.count }
            .prefix(12)
            .compactMap { $0.value.first }
        guard !prioritizedArtists.isEmpty else { return }

        Task { @MainActor in
            guard let directory = try? await NavidromeConnection.loadArtists(address: serverAddress, username: username, password: password) else { return }
            var fetched: [(String, NavidromeArtistInfo)] = []
            for name in prioritizedArtists {
                guard let artist = directory.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }),
                      let info = try? await NavidromeConnection.loadArtistInfo(address: serverAddress, username: username, password: password, artistID: artist.id) else { continue }
                fetched.append((name, info))
            }
            for (name, info) in fetched {
                artistInfoCache[artistCacheKey(name)] = info
                if selectedArtistName?.localizedCaseInsensitiveCompare(name) == .orderedSame {
                    selectedArtistInfo = info
                }
            }
            await ArtworkImageCache.preload(urls: fetched.compactMap { $0.1.preferredImageURL(serverAddress: serverAddress) })
        }
    }

    private func artistCacheKey(_ artist: String) -> String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    @ViewBuilder
    private func albumTile(_ album: NavidromeAlbum, size: CGFloat = 64) -> some View {
        if let coverArt = album.coverArt,
           let url = try? NavidromeConnection.coverArtURL(address: serverAddress, username: username, password: password, artworkID: coverArt, size: 180) {
            CachedArtworkView(url: url) {
                albumPlaceholder
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            albumPlaceholder.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var miniPlayerBar: some View {
        let playingAlbum = currentTrackID.flatMap { albumByTrackID[$0] } ?? selectedAlbum
        #if os(iOS)
        let queueIndex = nowPlaying.currentQueueIndex
        let canGoPrevious = queueIndex.map { $0 > 0 } ?? false
        let canGoNext = queueIndex.map { $0 + 1 < nowPlaying.queue.count } ?? false
        let queuedTrack = queueIndex.flatMap { nowPlaying.queue.indices.contains($0) ? nowPlaying.queue[$0] : nil }
        let track = queuedTrack.map {
            NavidromeTrack(id: $0.id, title: $0.title, artist: $0.artist, track: nil, duration: Int($0.duration), coverArt: $0.artworkID, bpm: nil)
        } ?? tracks.first { $0.id == currentTrackID }
        let currentArtworkURL: URL?
        if let queuedArtwork = queuedTrack?.artworkURL {
            currentArtworkURL = queuedArtwork
        } else if let track, let playingAlbum {
            currentArtworkURL = artworkURL(for: track, in: playingAlbum)
        } else {
            currentArtworkURL = nil
        }
        #else
        let track = tracks.first { $0.id == currentTrackID }
        let currentIndex = tracks.firstIndex { $0.id == currentTrackID }
        let canGoPrevious = currentIndex.map { $0 > tracks.startIndex } ?? false
        let canGoNext = currentIndex.map { $0 < tracks.index(before: tracks.endIndex) } ?? false
        let currentArtworkURL: URL?
        if let track, let playingAlbum { currentArtworkURL = artworkURL(for: track, in: playingAlbum) }
        else { currentArtworkURL = nil }
        #endif
        return VStack(spacing: 4) {
        HStack(spacing: 12) {
            if let track, playingAlbum != nil {
                TrackArtwork(
                    url: currentArtworkURL,
                    onTap: { showingNowPlaying = true }
                )
                .frame(width: 40, height: 40)
            } else {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(BreeHomePalette.lightOrange)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }

            VStack(alignment: .leading, spacing: 3) {
                Button { showingNowPlaying = true } label: {
                    MovingTickerText(
                        text: track?.title ?? playbackMessage ?? "Now Playing",
                        font: .subheadline.weight(.semibold)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open full screen player")
                if let artist = track?.artist ?? playingAlbum?.artist {
                    Button(artist) { showArtist(artist) }
                        .font(.caption)
                        .foregroundStyle(BreeHomePalette.lightOrange.opacity(0.92))
                        .lineLimit(1)
                        .buttonStyle(.plain)
                } else {
                    Text("BreeMusic")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
                if let playbackError = nowPlaying.playbackError {
                    Text("Playback failed: \(playbackError)")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.95))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button { skipCurrentQueue(by: -1) } label: {
                Image(systemName: "backward.end.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(canGoPrevious ? .white : .white.opacity(0.3))
                    .frame(width: 32, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoPrevious)
            .accessibilityLabel("Previous track")

            Button {
                if let track { play(track, opensNowPlaying: false) }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background {
                        if !isPaused { Circle().fill(BreeHomePalette.glassTint.opacity(0.32)) }
                        else { Circle().fill(.ultraThinMaterial.opacity(0.2)) }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPaused ? "Resume playback" : "Pause playback")

            Button { skipCurrentQueue(by: 1) } label: {
                Image(systemName: "forward.end.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(canGoNext ? .white : .white.opacity(0.3))
                    .frame(width: 32, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoNext)
            .accessibilityLabel("Next track")

        }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(.clear)
                .contentShape(RoundedRectangle(cornerRadius: 18))
                .onTapGesture { showingNowPlaying = true }
        }
        .background(.ultraThinMaterial.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        .glassEffect(.regular.tint(BreeHomePalette.glassTint.opacity(0.12)), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.045), lineWidth: 0.7)
        }
    }

    #if os(iOS)
    private var nowPlayingScreen: some View {
        let queuedTrack = nowPlaying.currentQueueIndex.flatMap { nowPlaying.queue.indices.contains($0) ? nowPlaying.queue[$0] : nil }
        let track = currentTrackID.flatMap { id in
            tracks.first { $0.id == id }
                ?? moodPlaylists.values.lazy.flatMap { $0 }.first { $0.id == id }
                ?? genrePlaylists.values.lazy.flatMap { $0 }.first { $0.id == id }
                ?? searchResults?.songs.first { $0.id == id }
        }
        let playingAlbum = currentTrackID.flatMap { albumByTrackID[$0] }
            ?? track.flatMap { track in albums.first { $0.id == (track.albumId ?? "") } }
            ?? selectedAlbum
        let currentArtworkURL: URL?
        if let queuedArtwork = queuedTrack?.artworkURL {
            currentArtworkURL = queuedArtwork
        } else if let track, let playingAlbum {
            currentArtworkURL = artworkURL(for: track, in: playingAlbum, size: 512)
        } else {
            currentArtworkURL = nil
        }
        let duration = max(TimeInterval(track?.duration ?? 0), nowPlaying.trackDuration)

        return NowPlayingDetailView(
            title: nowPlaying.title ?? track?.title ?? playbackMessage ?? "Now Playing",
            artist: nowPlaying.artist ?? queuedTrack?.artist ?? track?.artist ?? selectedAlbum?.artist ?? "BreeMusic",
            metadata: track,
            audioAnalysis: track.flatMap { audioAnalysisByTrackID[$0.id] },
            playbackError: nowPlaying.playbackError,
            artworkURL: currentArtworkURL,
            isPlaying: !isPaused,
            isFavorite: currentTrackID.map { favoriteTrackIDs.contains($0) } ?? false,
            isLiked: currentTrackID.map { likedTrackIDs.contains($0) } ?? false,
            isDisliked: currentTrackID.map { dislikedTrackIDs.contains($0) } ?? false,
            repeatMode: nowPlaying.repeatMode,
            isShuffleEnabled: nowPlaying.isShuffleEnabled,
            showingLyrics: $showingLyrics,
            lyrics: lyricLines,
            lyricSearchTargetLineID: lyricSearchTargetLineID,
            isLoadingLyrics: lyricsLoading,
            elapsedTime: nowPlaying.elapsedTime,
            duration: duration,
            onEqualizer: { showingEqualizer = true },
            onDismiss: {
                isSearchFieldFocused = false
                showingNowPlaying = false
            },
            onPlayPause: togglePlaybackFromPlayer,
            onPrevious: { skipCurrentQueue(by: -1) },
            onNext: { skipCurrentQueue(by: 1) },
            onRepeatModeChange: { nowPlaying.cycleRepeatMode() },
            onShuffleToggle: { nowPlaying.setShuffleEnabled(!nowPlaying.isShuffleEnabled) },
            onFavoriteToggle: { if let currentTrackID { toggleFavorite(currentTrackID) } },
            onLikeToggle: { if let currentTrackID { toggleReaction(currentTrackID, liked: true) } },
            onDislikeToggle: { if let currentTrackID { toggleReaction(currentTrackID, liked: false) } },
            onSeek: { nowPlaying.seek(to: $0) },
            onArtistSelected: showArtist
        )
        .task(id: nowPlaying.trackID) {
            guard let trackID = nowPlaying.trackID,
                  let track = nowPlaying.queue.first(where: { $0.id == trackID }) else {
                lyricLines = []
                lyricsLoading = false
                return
            }
            lyricLines = []
            lyricsLoading = true
            if pendingLyricsSearch?.trackID != trackID { lyricSearchTargetLineID = nil }
            do {
                let loadedLines = try await NavidromeConnection.loadLyrics(
                    address: serverAddress,
                    username: username,
                    password: password,
                    trackID: trackID,
                    artist: track.artist ?? "",
                    title: track.title
                )
                guard !Task.isCancelled, nowPlaying.trackID == trackID else { return }
                lyricLines = loadedLines
                if let pending = pendingLyricsSearch, pending.trackID == trackID,
                   let match = loadedLines.first(where: { $0.text.localizedCaseInsensitiveContains(pending.query) }) {
                    lyricSearchTargetLineID = match.id
                    if let startTime = match.startTime { nowPlaying.seek(to: startTime) }
                    pendingLyricsSearch = nil
                } else if pendingLyricsSearch?.trackID == trackID {
                    pendingLyricsSearch = nil
                }
            } catch {
                guard !Task.isCancelled, nowPlaying.trackID == trackID else { return }
                lyricLines = []
            }
            if nowPlaying.trackID == trackID { lyricsLoading = false }
        }
    }
    #endif

    private var artistNames: [String] {
        var namesByKey: [String: String] = [:]
        for name in artistDirectory.map(\.name) + albums.compactMap(\.artist) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = artistCacheKey(trimmed)
            if namesByKey[key] == nil { namesByKey[key] = trimmed }
        }
        return namesByKey.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var displayedAlbums: [NavidromeAlbum] {
        switch albumSortOrder {
        case .album:
            return albums.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .artist:
            return albums.sorted {
                let artistOrder = ($0.artist ?? "").localizedStandardCompare($1.artist ?? "")
                return artistOrder == .orderedSame
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : artistOrder == .orderedAscending
            }
        }
    }

    private var artistAlbumGroups: [(artist: String, albums: [NavidromeAlbum])] {
        let grouped = Dictionary(grouping: albums) { album in
            let artist = album.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return artist.isEmpty ? "Unknown artist" : artist
        }
        return grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { artist in
            (artist: artist, albums: (grouped[artist] ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }

    private func showArtist(_ artist: String) {
        let name = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        recentSearchedArtists.removeAll { artistCacheKey($0) == artistCacheKey(name) }
        recentSearchedArtists.insert(name, at: 0)
        recentSearchedArtists = Array(recentSearchedArtists.prefix(5))
        UserDefaults.standard.set(recentSearchedArtists, forKey: "BreeMusic.RecentArtists")
        selectedArtistName = name
        let dismissingWindow = showingNowPlaying || showingAlbumDetail
        showingNowPlaying = false
        showingAlbumDetail = false
        if dismissingWindow {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                showingArtistBrowser = true
            }
        } else {
            showingArtistBrowser = true
        }
    }

    private func openAlbumFromArtist(_ album: NavidromeAlbum) {
        showingArtistBrowser = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            openAlbum(album)
        }
    }

    private var albumPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [BreeHomePalette.lightOrange.opacity(0.45), BreeHomePalette.burntOrange.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note").font(.title2).foregroundStyle(.white.opacity(0.85))
        }
    }

    #if os(iOS)
    private var lockScreen: some View {
        VStack(spacing: 18) {
            Image("BreeMusicLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text("BreeMusic")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Image(systemName: "faceid")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(BreeHomePalette.lightOrange)
            Button(action: unlock) {
                Label("Unlock", systemImage: "faceid")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            if let unlockMessage {
                Text(unlockMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [BreeHomePalette.surface, BreeHomePalette.surface.opacity(0.88), BreeHomePalette.burntOrange.opacity(0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(BreeHomePalette.lightOrange.opacity(0.16))
                    .frame(width: 260, height: 260)
                    .offset(x: 75, y: -45)
            }
        }
        .ignoresSafeArea()
    }

    private func unlock() {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock BreeMusic and restore your Navidrome login.") { success, error in
            DispatchQueue.main.async {
                guard success else {
                    unlockMessage = error?.localizedDescription ?? "Authentication was not completed."
                    return
                }
                let credentials = SecureLoginStore.load()
                if let credentials {
                    username = credentials.username
                    password = credentials.password
                }
                unlockMessage = nil
                isLocked = false
                if credentials != nil {
                    connect(preservingPlayback: true)
                }
            }
        }
    }

    private func scheduleRelock() {
        relockTask?.cancel()
        relockTask = Task {
            do {
                try await Task.sleep(for: .seconds(300))
            } catch {
                return
            }
            guard scenePhase == .background else { return }
            isLocked = true
        }
    }
    #endif

    private func connect(preservingPlayback: Bool = false) {
        guard !isConnecting else { return }
        isConnecting = true
        connectionResult = nil
        albums = []
        if !restoreMoodMixCache(for: username) {
            moodPlaylists = [:]
            genrePlaylists = [:]
            moodPlaylistsLoaded = false
        }
        selectedAlbum = nil
        tracks = []
        trackLoadError = nil
        if !preservingPlayback { stopPlayback() }

        Task {
            defer { isConnecting = false }

            do {
                let addresses = [Self.tailnetServerAddress, Self.lastKnownTailnetIP]
                var connectedAddress: String?
                var connectedLibrary: NavidromeLibrary?
                var lastConnectionError: Error?

                for address in addresses {
                    do {
                        connectedLibrary = try await NavidromeConnection.loadLibrary(
                            address: address,
                            username: username,
                            password: password
                        )
                        connectedAddress = address
                        break
                    } catch {
                        lastConnectionError = error
                        if let connectionError = error as? ConnectionError,
                           case .serverRejected = connectionError {
                            throw error
                        }
                    }
                }

                guard let connectedAddress, let library = connectedLibrary else {
                    throw lastConnectionError ?? ConnectionError.timedOut
                }
                serverAddress = connectedAddress
                albums = library.albums
                #if os(iOS)
                audioAnalysisByTrackID = Self.loadAudioAnalysisCache(for: username)
                #endif
                artistDirectory = (try? await NavidromeConnection.loadArtists(
                    address: connectedAddress,
                    username: username,
                    password: password
                )) ?? []
                for track in moodPlaylists.values.joined() {
                    if let album = albums.first(where: { $0.id == (track.albumId ?? "") }) {
                        albumByTrackID[track.id] = album
                    }
                }
                for track in genrePlaylists.values.joined() {
                    if let album = albums.first(where: { $0.id == (track.albumId ?? "") }) {
                        albumByTrackID[track.id] = album
                    }
                }
                preloadAlbumInformation(for: library.albums)
                randomHomepageArtists = Array(Set(library.albums.compactMap { $0.artist?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).shuffled().prefix(5).map { $0 }
                preloadArtistInformation(for: library.albums)
                loadMoodPlaylists()
                Task {
                    await ArtworkImageCache.preload(urls: library.albums.compactMap { album in
                        guard let coverArt = album.coverArt else { return nil }
                        return try? NavidromeConnection.coverArtURL(
                            address: connectedAddress,
                            username: username,
                            password: password,
                            artworkID: coverArt,
                            size: 180
                        )
                    })
                }
                var credentialNotice = ""
                #if os(iOS)
                do {
                    try SecureLoginStore.save(username: username, password: password)
                } catch {
                    credentialNotice = " Your login could not be saved securely, so you may need to enter it again next time."
                }
                #endif
                connectionResult = ConnectionResult(
                    isSuccess: true,
                    title: "Connected",
                    detail: (connectedAddress == Self.tailnetServerAddress
                        ? "Using automatic Tailscale DNS. "
                        : "Using the last known Tailscale IP; automatic IP changes require Tailscale DNS to resolve. ") + credentialNotice
                )
                #if os(iOS)
                scheduleAutomaticAudioAnalysis()
                #endif
            } catch {
                connectionResult = ConnectionResult(
                    isSuccess: false,
                    title: "Could not connect",
                    detail: error.localizedDescription
                )
            }
        }
    }

    private func refreshServerAddressOnForeground() {
        guard !isLocked,
              !isConnecting,
              !username.isEmpty,
              !password.isEmpty else { return }

        Task {
            for address in [Self.tailnetServerAddress, Self.lastKnownTailnetIP] {
                do {
                    try await NavidromeConnection.checkServer(
                        address: address,
                        username: username,
                        password: password
                    )
                    serverAddress = address
                    scheduleAutomaticAudioAnalysis()
                    return
                } catch {
                    continue
                }
            }

            // Keep future requests on MagicDNS so the next attempt can recover
            // if the Windows PC's Tailscale address has changed.
            serverAddress = Self.tailnetServerAddress
        }
    }

    private func loadTracks(for album: NavidromeAlbum) {
        selectedAlbum = album
        tracks = []
        trackLoadError = nil
        isLoadingTracks = true

        Task {
            do {
                let loadedTracks = try await NavidromeConnection.loadTracks(
                    address: serverAddress,
                    username: username,
                    password: password,
                    albumID: album.id
                )
                guard selectedAlbum?.id == album.id else { return }
                tracks = loadedTracks
                for track in loadedTracks { albumByTrackID[track.id] = album }
            } catch {
                guard selectedAlbum?.id == album.id else { return }
                trackLoadError = error.localizedDescription
            }
            if selectedAlbum?.id == album.id {
                isLoadingTracks = false
            }
        }
    }

    private func toggleArtistAlbum(_ album: NavidromeAlbum) {
        if expandedArtistAlbumID == album.id {
            withAnimation(.smooth(duration: 0.24)) {
                expandedArtistAlbumID = nil
            }
            return
        }

        withAnimation(.smooth(duration: 0.24)) {
            expandedArtistAlbumID = album.id
        }
        if selectedAlbum?.id != album.id || (tracks.isEmpty && !isLoadingTracks) {
            loadTracks(for: album)
        }
    }

    @ViewBuilder
    private func artistAlbumTracks(_ album: NavidromeAlbum) -> some View {
        if selectedAlbum?.id == album.id && isLoadingTracks {
            ProgressView("Loading tracks…")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 64)
                .padding(.vertical, 10)
        } else if selectedAlbum?.id == album.id, let trackLoadError {
            Text(trackLoadError)
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(.leading, 64)
        } else if selectedAlbum?.id == album.id {
            VStack(spacing: 3) {
                ForEach(tracks) { track in
                    Button { play(track, opensNowPlaying: false) } label: {
                        HStack(spacing: 10) {
                            Text(track.track.map(String.init) ?? "•")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: 24, alignment: .trailing)
                            Text(track.title)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            if let duration = track.duration {
                                Text(Self.durationLabel(duration))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            Image(systemName: currentTrackID == track.id && !isPaused ? "pause.fill" : "play.fill")
                                .font(.caption)
                                .foregroundStyle(BreeHomePalette.lightOrange)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 52)
        }
    }

    private static func moodMixCacheURL(for username: String) -> URL {
        let stableAccountKey = "\(tailnetServerAddress.lowercased())\n\(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        let filename = SHA256.hash(data: Data(stableAccountKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined() + ".json"
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BreeMusic", isDirectory: true)
            .appendingPathComponent("MoodMixes", isDirectory: true)
        return supportDirectory.appendingPathComponent(filename)
    }

    private func restoreMoodMixCache(for account: String) -> Bool {
        let url = Self.moodMixCacheURL(for: account)
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(BreeMoodMixCache.self, from: data),
              cache.playlists.keys.contains(where: { moodMixNames.contains($0) }) else { return false }
        moodPlaylists = cache.playlists.filter { moodMixNames.contains($0.key) }
        genrePlaylists = cache.genres
        moodPlaylistsLoaded = true
        return true
    }

    #if os(iOS)
    private static func audioAnalysisCacheKey(for username: String) -> String {
        let accountKey = "\(tailnetServerAddress.lowercased())\n\(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        let digest = SHA256.hash(data: Data(accountKey.utf8)).map { String(format: "%02x", $0) }.joined()
        return "BreeMusic.AudioAnalysis.\(digest)"
    }

    private static func loadAudioAnalysisCache(for username: String) -> [String: BreeTrackAudioAnalysis] {
        guard let data = UserDefaults.standard.data(forKey: audioAnalysisCacheKey(for: username)),
              let values = try? JSONDecoder().decode([String: BreeTrackAudioAnalysis].self, from: data) else { return [:] }
        return values
    }

    private func persistAudioAnalysisCache() {
        guard let data = try? JSONEncoder().encode(audioAnalysisByTrackID) else { return }
        UserDefaults.standard.set(data, forKey: Self.audioAnalysisCacheKey(for: username))
    }

    private func scheduleAutomaticAudioAnalysis() {
        Task {
            while isLoadingMoodPlaylists {
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard connectionResult?.isSuccess == true, !isLocked else { return }
            analyzeLibraryAudio(refreshAll: true)
        }
    }

    private func analyzeLibraryAudio(refreshAll: Bool) {
        guard !isAnalyzingLibraryAudio else { return }
        isAnalyzingLibraryAudio = true
        audioAnalysisTracksProcessed = 0

        Task {
            defer {
                isAnalyzingLibraryAudio = false
            }
            do {
                var libraryTracks: [NavidromeTrack] = []
                for album in albums {
                    let albumTracks = try await NavidromeConnection.loadTracks(
                        address: serverAddress,
                        username: username,
                        password: password,
                        albumID: album.id
                    )
                    for track in albumTracks { albumByTrackID[track.id] = album }
                    libraryTracks.append(contentsOf: albumTracks)
                }

                var seen = Set<String>()
                let uniqueTracks = libraryTracks.filter { seen.insert($0.id).inserted }
                let tracksToAnalyze = refreshAll ? uniqueTracks : uniqueTracks.filter { audioAnalysisByTrackID[$0.id] == nil }
                guard !tracksToAnalyze.isEmpty else {
                    return
                }

                for track in tracksToAnalyze {
                    do {
                        let streamURL = try NavidromeConnection.streamURL(
                            address: serverAddress,
                            username: username,
                            password: password,
                            trackID: track.id,
                            maxBitRate: 64
                        )
                        let genres = (track.genres?.map(\.name) ?? []) + [track.genre ?? ""]
                        audioAnalysisByTrackID[track.id] = try await BreeTrackAudioAnalyzer.analyze(url: streamURL, genres: genres)
                    } catch {
                        print("Audio analysis failed for \(track.id): \(error.localizedDescription)")
                    }
                    audioAnalysisTracksProcessed += 1
                    if audioAnalysisTracksProcessed.isMultiple(of: 5) {
                        persistAudioAnalysisCache()
                    }
                }
                persistAudioAnalysisCache()
                loadMoodPlaylists()
            } catch {
                print("Could not read library for audio analysis: \(error.localizedDescription)")
            }
        }
    }
    #endif

    private func persistMoodMixCache(
        _ playlists: [String: [NavidromeTrack]],
        genres: [String: [NavidromeTrack]],
        for account: String
    ) {
        var tracksByID: [String: NavidromeTrack] = [:]
        for track in playlists.values.joined() { tracksByID[track.id] = track }
        for track in genres.values.joined() { tracksByID[track.id] = track }
        let cache = BreeMoodMixCache(
            updatedAt: Date(),
            tracksByID: tracksByID,
            trackIDsByMood: playlists.mapValues { $0.map(\.id) },
            trackIDsByGenre: genres.mapValues { $0.map(\.id) }
        )
        let url = Self.moodMixCacheURL(for: account)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(cache).write(to: url, options: .atomic)
        } catch {
            print("Could not save mood mix cache: \(error)")
        }
    }

    private func beginMoodRefreshBackgroundTime() {
        #if os(iOS)
        guard moodRefreshBackgroundTask == .invalid else { return }
        moodRefreshBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Refresh BreeMusic mood mixes") {
            Task { @MainActor in endMoodRefreshBackgroundTime() }
        }
        #endif
    }

    private func endMoodRefreshBackgroundTime() {
        #if os(iOS)
        guard moodRefreshBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(moodRefreshBackgroundTask)
        moodRefreshBackgroundTask = .invalid
        #endif
    }

    private func openAlbum(_ album: NavidromeAlbum) {
        recordAlbumOpened(album)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            selectedAlbum = album
            showingAlbumDetail = true
        }
        loadTracks(for: album)
    }

    private func recordAlbumOpened(_ album: NavidromeAlbum) {
        recentOpenedAlbums.removeAll { $0.album.id == album.id }
        recentOpenedAlbums.append(RecentAlbumOpen(album: album, date: Date()))
        recentOpenedAlbums = Array(recentOpenedAlbums.suffix(250))
        if let data = try? JSONEncoder().encode(recentOpenedAlbums) {
            UserDefaults.standard.set(data, forKey: "BreeMusic.RecentOpenedAlbums")
        }
    }

    private func loadMoodPlaylists() {
        guard !isLoadingMoodPlaylists else { return }
        isLoadingMoodPlaylists = true
        moodAlbumsProcessed = 0
        moodAlbumsTotal = albums.count
        if moodPlaylists.isEmpty { moodPlaylistsLoaded = false }
        Task {
            defer {
                isLoadingMoodPlaylists = false
                endMoodRefreshBackgroundTime()
            }
            do {
                var libraryTracks: [NavidromeTrack] = []
                for (index, album) in albums.enumerated() {
                    let albumTracks = try await NavidromeConnection.loadTracks(
                        address: serverAddress,
                        username: username,
                        password: password,
                        albumID: album.id
                    )
                    for track in albumTracks { albumByTrackID[track.id] = album }
                    libraryTracks.append(contentsOf: albumTracks)
                    moodAlbumsProcessed = index + 1
                }
                let categories = moodMixNames
                var grouped: [String: [NavidromeTrack]] = Dictionary(uniqueKeysWithValues: categories.map { ($0, []) })
                var groupedGenres: [String: [NavidromeTrack]] = [:]
                var genreNamesByKey: [String: String] = [:]
                for track in libraryTracks {
                    #if os(iOS)
                    let analyzedCategories = audioAnalysisByTrackID[track.id]?.suggestedMixes ?? []
                    #else
                    let analyzedCategories: [String] = []
                    #endif
                    for category in Set(moodCategories(for: track) + analyzedCategories) {
                        grouped[category, default: []].append(track)
                    }
                    let trackGenres = (track.genres?.map(\.name) ?? []) + [track.genre ?? ""]
                    for rawGenre in trackGenres {
                        let genre = rawGenre.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !genre.isEmpty else { continue }
                        let key = genre.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                        let displayName = genreNamesByKey[key] ?? genre
                        genreNamesByKey[key] = displayName
                        groupedGenres[displayName, default: []].append(track)
                    }
                }
                if !libraryTracks.isEmpty {
                    for category in categories where grouped[category, default: []].isEmpty {
                        let relevantTracks = libraryTracks.compactMap { track -> (NavidromeTrack, Int)? in
                            let score = moodFallbackScore(track, for: category)
                            return score >= 35 ? (track, score) : nil
                        }.sorted { left, right in
                            left.1 == right.1
                                ? left.0.title.localizedStandardCompare(right.0.title) == .orderedAscending
                                : left.1 > right.1
                        }
                        grouped[category] = Array(relevantTracks.prefix(50).map(\.0))
                    }
                }
                let refreshedPlaylists: [String: [NavidromeTrack]] = libraryTracks.isEmpty ? [:] : grouped.mapValues { tracks in
                    var seen = Set<String>()
                    return tracks.filter { seen.insert($0.id).inserted }
                }
                let refreshedGenres = groupedGenres.mapValues { tracks in
                    var seen = Set<String>()
                    return tracks.filter { seen.insert($0.id).inserted }
                }
                moodPlaylists = refreshedPlaylists
                genrePlaylists = refreshedGenres
                if let selectedArtistGenre, refreshedGenres[selectedArtistGenre] == nil {
                    self.selectedArtistGenre = nil
                }
                moodPlaylistsLoaded = true
                persistMoodMixCache(refreshedPlaylists, genres: refreshedGenres, for: username)
            } catch {
                if !moodPlaylistsLoaded {
                    playbackMessage = "Could not load listening mix information: \(error.localizedDescription)"
                }
            }
        }
    }

    private func playMoodPlaylist(_ mixName: String, startingWith trackID: String? = nil) {
        activeMoodMix = mixName
        activeGenre = nil
        let mixTracks = moodPlaylists[mixName] ?? []
        guard !mixTracks.isEmpty else { return }
        let tempoValues = mixTracks.compactMap { $0.bpm.map(Double.init) }.filter { (30...240).contains($0) }.sorted()
        let medianBPM: Double? = tempoValues.isEmpty ? nil : tempoValues[tempoValues.count / 2]
        #if os(iOS)
        BreeEQSettings.shared.setMixProfile(BreeMixEQProfile.make(mood: mixName, averageBPM: medianBPM))
        #endif
        playTracksAsMix(
            name: mixName,
            tracks: mixTracks,
            startingWith: trackID
        )
    }

    private func playGenrePlaylist(_ genre: String) {
        activeGenre = genre
        activeMoodMix = nil
        #if os(iOS)
        BreeEQSettings.shared.setMixProfile(nil)
        #endif
        playTracksAsMix(name: genre, tracks: genrePlaylists[genre] ?? [])
    }

    private func playTracksAsMix(name: String, tracks: [NavidromeTrack], startingWith trackID: String? = nil) {
        var matchingTracks = rhythmAwareShuffle(tracks)
        guard !matchingTracks.isEmpty else { return }
        if let trackID, let startIndex = matchingTracks.firstIndex(where: { $0.id == trackID }) {
            matchingTracks = Array(matchingTracks[startIndex...]) + Array(matchingTracks[..<startIndex])
        }
        recordRecentMix(name)
        #if os(iOS)
        do {
            let queue = try matchingTracks.map { track -> BreeQueuedTrack in
                let album = albumByTrackID[track.id] ?? NavidromeAlbum(
                    id: track.albumId ?? track.id,
                    name: track.album ?? "Unknown album",
                    artist: track.artist,
                    year: track.year,
                    songCount: nil,
                    coverArt: track.coverArt
                )
                return BreeQueuedTrack(
                    id: track.id,
                    title: track.title,
                    artist: track.artist ?? album.artist ?? "Unknown artist",
                    album: album.name,
                    duration: TimeInterval(track.duration ?? 0),
                    bpm: track.bpm.map(Double.init),
                    artworkID: track.coverArt ?? album.coverArt ?? track.id,
                    artworkURL: artworkURL(for: track, in: album, size: 512),
                    url: try NavidromeConnection.streamURL(address: serverAddress, username: username, password: password, trackID: track.id, maxBitRate: selectedStreamBitRate)
                )
            }
            nowPlaying.setShuffleEnabled(true)
            nowPlaying.setCrossfadeEnabled(true)
            nowPlaying.setBeatSyncEnabled(true)
            startingTrackID = queue.first?.id
            Task {
                do {
                    try await nowPlaying.start(queue: queue, at: 0, preserveQueueOrder: true)
                    playbackMessage = "\(name) mix"
                } catch {
                    BreeEQSettings.shared.setMixProfile(nil)
                    if activeMoodMix == name { activeMoodMix = nil }
                    startingTrackID = nil
                    playbackMessage = "Could not play \(name) mix: \(error.localizedDescription)"
                }
            }
        } catch {
            #if os(iOS)
            BreeEQSettings.shared.setMixProfile(nil)
            #endif
            if activeMoodMix == name { activeMoodMix = nil }
            playbackMessage = "Could not prepare \(name) mix: \(error.localizedDescription)"
        }
        #else
        guard let track = matchingTracks.first,
              let streamURL = try? NavidromeConnection.streamURL(address: serverAddress, username: username, password: password, trackID: track.id, maxBitRate: selectedStreamBitRate) else { return }
        player?.pause()
        player = AVPlayer(url: streamURL)
        currentTrackID = track.id
        isPaused = false
        playbackMessage = "\(name) mix"
        player?.play()
        #endif
    }

    private func rhythmAwareShuffle(_ tracks: [NavidromeTrack]) -> [NavidromeTrack] {
        guard tracks.count > 2 else { return tracks.shuffled() }
        var remaining = tracks.shuffled()
        let firstPool = remaining.indices.filter { trackTempo(remaining[$0]) != nil }
        let firstIndex = firstPool.randomElement() ?? remaining.indices.randomElement()!
        var ordered = [remaining.remove(at: firstIndex)]

        while let previous = ordered.last, !remaining.isEmpty {
            let scored = remaining.enumerated().map { index, candidate in
                (index: index, distance: rhythmTransitionCost(from: previous, to: candidate, recent: ordered.suffix(3)))
            }.sorted { $0.distance < $1.distance }
            guard let bestDistance = scored.first?.distance else { break }
            let closeOptions = scored.prefix(6).filter { $0.distance <= bestDistance + 1.1 }
            let choice = closeOptions.randomElement() ?? scored[0]
            ordered.append(remaining.remove(at: choice.index))
        }
        return ordered
    }

    private func rhythmTransitionCost(
        from previous: NavidromeTrack,
        to candidate: NavidromeTrack,
        recent: ArraySlice<NavidromeTrack>
    ) -> Double {
        let previousTempo = trackTempo(previous)
        let candidateTempo = trackTempo(candidate)
        let tempoCost: Double
        if let previousTempo, let candidateTempo {
            let ratio = previousTempo / candidateTempo
            tempoCost = min(abs(12 * log2(ratio)), min(abs(12 * log2(ratio * 2)), abs(12 * log2(ratio / 2)))) * 1.15
        } else {
            tempoCost = previousTempo == nil && candidateTempo == nil ? 0.3 : 1.6
        }

        let previousKey = camelotPosition(musicalKey(for: previous))
        let candidateKey = camelotPosition(musicalKey(for: candidate))
        let keyCost: Double
        if let previousKey, let candidateKey {
            let rawSteps = abs(previousKey.number - candidateKey.number)
            let wheelSteps = min(rawSteps, 12 - rawSteps)
            keyCost = (previousKey.mode == candidateKey.mode ? Double(wheelSteps) : Double(wheelSteps) + 1.0) * 0.55
        } else {
            keyCost = 0
        }

        let previousGenres = normalizedTags((previous.genres?.map(\.name) ?? []) + [previous.genre ?? ""])
        let candidateGenres = normalizedTags((candidate.genres?.map(\.name) ?? []) + [candidate.genre ?? ""])
        let genreCost = !previousGenres.isEmpty && !candidateGenres.isEmpty && previousGenres.isDisjoint(with: candidateGenres) ? 0.8 : 0

        let previousMoods = normalizedTags((previous.moods ?? []) + (previous.groupings ?? []))
        let candidateMoods = normalizedTags((candidate.moods ?? []) + (candidate.groupings ?? []))
        let moodCost = !previousMoods.isEmpty && !candidateMoods.isEmpty && previousMoods.isDisjoint(with: candidateMoods) ? 0.45 : 0

        let candidateArtist = artistCacheKey(candidate.artist ?? "")
        let repeatsRecentArtist = !candidateArtist.isEmpty && recent.contains { artistCacheKey($0.artist ?? "") == candidateArtist }
        return tempoCost + keyCost + genreCost + moodCost + (repeatsRecentArtist ? 0.55 : 0)
    }

    private func trackTempo(_ track: NavidromeTrack) -> Double? {
        #if os(iOS)
        if let analyzedTempo = audioAnalysisByTrackID[track.id]?.beatsPerMinute,
           (30...240).contains(analyzedTempo) { return analyzedTempo }
        #endif
        guard let bpm = track.bpm, (30...240).contains(bpm) else { return nil }
        return Double(bpm)
    }

    private func normalizedTags(_ tags: [String]) -> Set<String> {
        Set(tags.compactMap { tag in
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return normalized.isEmpty ? nil : normalized
        })
    }

    private func camelotPosition(_ rawKey: String?) -> (number: Int, mode: Character)? {
        guard let rawKey else { return nil }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let characters = Array(key)
        if characters.count >= 2,
           let number = Int(String(characters.dropLast())),
           (1...12).contains(number),
           let mode = characters.last,
           mode == "a" || mode == "b" {
            return (number, mode)
        }

        let note = key.replacingOccurrences(of: "major", with: "")
            .replacingOccurrences(of: "minor", with: "m")
            .replacingOccurrences(of: " ", with: "")
        let major: [String: (Int, Character)] = [
            "c": (8, "b"), "g": (9, "b"), "d": (10, "b"), "a": (11, "b"), "e": (12, "b"),
            "b": (1, "b"), "f#": (2, "b"), "gb": (2, "b"), "c#": (3, "b"), "db": (3, "b"),
            "g#": (4, "b"), "ab": (4, "b"), "d#": (5, "b"), "eb": (5, "b"), "a#": (6, "b"),
            "bb": (6, "b"), "f": (7, "b")
        ]
        let minor: [String: (Int, Character)] = [
            "am": (8, "a"), "em": (9, "a"), "bm": (10, "a"), "f#m": (11, "a"), "gbm": (11, "a"),
            "c#m": (12, "a"), "dbm": (12, "a"), "g#m": (1, "a"), "abm": (1, "a"), "d#m": (2, "a"),
            "ebm": (2, "a"), "a#m": (3, "a"), "bbm": (3, "a"), "fm": (4, "a"), "cm": (5, "a"),
            "gm": (6, "a"), "dm": (7, "a")
        ]
        return note.hasSuffix("m") ? minor[note] : major[note]
    }

    private func musicalKey(for track: NavidromeTrack) -> String? {
        if let key = track.initialKey ?? track.key, !key.isEmpty { return key }
        let pattern = #"(?i)(?:camelot|initial\s+key|musical\s+key|key)\s*[:=]\s*((?:1[0-2]|[1-9])\s*[ab]|[a-g](?:#|b)?\s*(?:major|minor|maj|min|m)?)"#
        let candidates = [track.comment ?? ""] + (track.groupings ?? [])
        for text in candidates {
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(text[range])
            if let valueRange = match.range(of: #"(?:1[0-2]|[1-9])\s*[ab]|[a-g](?:#|b)?\s*(?:major|minor|maj|min|m)?$"#, options: .regularExpression) {
                return String(match[valueRange]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func moodCategories(for track: NavidromeTrack) -> [String] {
        let genreText = ((track.genres?.map(\.name) ?? []) + [track.genre ?? ""]).joined(separator: " ").lowercased()
        let moodText = ((track.moods ?? []) + (track.groupings ?? [])).joined(separator: " ").lowercased()
        let bpm = trackTempo(track)
        let taggedCategories = moodMixNames.filter { mix in
            let keywords = mixKeywords(for: mix)
            let moodMatch = keywords.contains(where: moodText.contains)
            let genreMatch = mixGenreKeywords(for: mix).contains(where: genreText.contains)
            guard moodMatch || genreMatch else { return false }
            guard let bpm else { return true }
            return moodMatch || tempoFit(bpm, for: mix) != nil
        }
        guard let bpm else { return taggedCategories }
        let tempoCategories = moodMixNames
            .compactMap { mix in tempoFit(bpm, for: mix).map { (mix, $0) } }
            .sorted { $0.1 < $1.1 }
            .prefix(2)
            .map(\.0)
        let allMatches = Set(taggedCategories + tempoCategories)
        return moodMixNames.filter { allMatches.contains($0) }
    }

    private func moodFallbackScore(_ track: NavidromeTrack, for mix: String) -> Int {
        let genreText = ((track.genres?.map(\.name) ?? []) + [track.genre ?? ""]).joined(separator: " ").lowercased()
        let moodText = ((track.moods ?? []) + (track.groupings ?? [])).joined(separator: " ").lowercased()
        let genreScore = mixGenreKeywords(for: mix).filter(genreText.contains).count * 50
        let moodScore = mixKeywords(for: mix).filter(moodText.contains).count * 75
        let tempoScore = trackTempo(track).flatMap { tempoFit($0, for: mix) }
            .map { max(0, 60 - Int($0 * 5)) } ?? 0
        #if os(iOS)
        let audioScore = Int((audioAnalysisByTrackID[track.id]?.mixScores[mix] ?? 0) * 100)
        #else
        let audioScore = 0
        #endif
        return max(genreScore + moodScore + tempoScore, audioScore)
    }

    private func moodTargetBPM(_ mix: String) -> Double {
        switch mix {
        case "Morning Coffee & Ease-In": 82
        case "Deep Work & Coding Focus": 80
        case "Midday Energy & Feel-Good Boost": 118
        case "High-Intensity & Running": 150
        case "Cooking & Hosting Dinner": 96
        case "Daytime Road Trip & Cruising": 120
        case "Late-Night Drive": 96
        case "Gaming & Immersive Sessions": 110
        case "Evening Unwind & Lounge": 78
        default: 48
        }
    }

    private func moodBPMRange(_ mix: String) -> ClosedRange<Double> {
        switch mix {
        case "Morning Coffee & Ease-In": 55...100
        case "Deep Work & Coding Focus": 55...110
        case "Midday Energy & Feel-Good Boost": 110...125
        case "High-Intensity & Running": 130...200
        case "Cooking & Hosting Dinner": 75...115
        case "Daytime Road Trip & Cruising": 95...140
        case "Late-Night Drive": 70...120
        case "Gaming & Immersive Sessions": 80...140
        case "Evening Unwind & Lounge": 55...105
        default: 30...70
        }
    }

    private func tempoFit(_ bpm: Double, for mix: String) -> Double? {
        let range = moodBPMRange(mix)
        let target = moodTargetBPM(mix)
        return [bpm, bpm / 2, bpm * 2]
            .filter(range.contains)
            .map { abs(12 * log2($0 / target)) }
            .min()
    }

    private func mixGenreKeywords(for mix: String) -> [String] {
        switch mix {
        case "Morning Coffee & Ease-In": ["acoustic", "indie folk", "folk", "singer-songwriter", "instrumental", "piano", "soft rock"]
        case "Deep Work & Coding Focus": ["lo-fi", "lofi", "ambient", "instrumental", "minimal", "downtempo", "trip-hop"]
        case "Midday Energy & Feel-Good Boost": ["pop", "funk", "dance-pop", "dance pop", "disco", "soul", "upbeat"]
        case "High-Intensity & Running": ["edm", "electronic dance", "dance", "hip-hop", "hip hop", "drum and bass", "dnb", "workout", "hard rock", "metal"]
        case "Cooking & Hosting Dinner": ["neo-soul", "neosoul", "bossa nova", "soul", "jazz", "lounge", "latin jazz"]
        case "Daytime Road Trip & Cruising": ["classic rock", "indie rock", "rock", "pop rock", "country rock", "americana", "road trip"]
        case "Late-Night Drive": ["alternative r&b", "r&b", "rnb", "deep house", "house", "downtempo", "trip-hop", "ambient electronic"]
        case "Gaming & Immersive Sessions": ["synthwave", "future garage", "cinematic", "electronic", "ambient", "soundtrack", "instrumental", "darksynth"]
        case "Evening Unwind & Lounge": ["chillhop", "smooth jazz", "jazz", "downtempo", "lounge", "chillout", "lo-fi", "lofi"]
        default: ["solo piano", "piano", "ambient", "minimalist", "new age", "sleep", "meditation", "drone"]
        }
    }

    private func mixKeywords(for mix: String) -> [String] {
        switch mix {
        case "Morning Coffee & Ease-In": ["morning", "gentle", "warm", "ease in", "ease-in", "sunrise"]
        case "Deep Work & Coding Focus": ["focus", "coding", "deep work", "study", "no vocal", "no vocals", "minimal lyrics"]
        case "Midday Energy & Feel-Good Boost": ["feel good", "feel-good", "upbeat", "bright", "energetic", "midday"]
        case "High-Intensity & Running": ["high energy", "high-intensity", "running", "workout", "training", "heavy bass"]
        case "Cooking & Hosting Dinner": ["cooking", "dinner", "hosting", "groovy", "laid-back", "laid back"]
        case "Daytime Road Trip & Cruising": ["road trip", "cruising", "driving", "sing-along", "sing along", "upbeat"]
        case "Late-Night Drive": ["late-night", "late night", "night drive", "moody", "atmospheric", "bass-heavy"]
        case "Gaming & Immersive Sessions": ["gaming", "immersive", "cinematic", "soundtrack", "instrumental"]
        case "Evening Unwind & Lounge": ["evening", "unwind", "relaxing", "lounge", "chill", "smooth"]
        default: ["sleep", "deep relaxation", "calm", "minimalist", "ultraslow", "ultra slow", "no beats", "zero beats"]
        }
    }

    private func saveMoodPlaylist(_ mood: String) {
        let trackIDs = (moodPlaylists[mood] ?? []).map(\.id)
        guard !trackIDs.isEmpty else { return }
        moodPlaylistStatus[mood] = "Saving…"
        Task {
            do {
                try await NavidromeConnection.createPlaylist(
                    address: serverAddress,
                    username: username,
                    password: password,
                    name: "BreeMusic · \(mood.capitalized)",
                    trackIDs: trackIDs
                )
                moodPlaylistStatus[mood] = "Saved"
            } catch {
                moodPlaylistStatus[mood] = nil
                playbackMessage = "Could not save mood playlist: \(error.localizedDescription)"
            }
        }
    }

    private func startLibraryRadio() {
        guard !isStartingRadio else { return }
        isStartingRadio = true
        activeMoodMix = nil
        activeGenre = nil
        #if os(iOS)
        BreeEQSettings.shared.setMixProfile(nil)
        #endif
        Task {
            defer { isStartingRadio = false }
            do {
                let randomTracks = try await NavidromeConnection.loadRandomTracks(
                    address: serverAddress,
                    username: username,
                    password: password,
                    count: 50
                )
                guard !randomTracks.isEmpty else {
                    playbackMessage = "No tracks were returned for BreeMusic Radio."
                    return
                }
                recordRecentMix("BreeMusic Radio")
                #if os(iOS)
                let queue = try randomTracks.map { track -> BreeQueuedTrack in
                    let albumName = track.album ?? "Unknown album"
                    let artistName = track.artist ?? "Unknown artist"
                    let album = albums.first(where: { $0.id == track.albumId }) ?? NavidromeAlbum(
                        id: track.albumId ?? track.id,
                        name: albumName,
                        artist: artistName,
                        year: track.year,
                        songCount: nil,
                        coverArt: track.coverArt
                    )
                    albumByTrackID[track.id] = album
                    return BreeQueuedTrack(
                        id: track.id,
                        title: track.title,
                        artist: artistName,
                        album: albumName,
                        duration: TimeInterval(track.duration ?? 0),
                        bpm: track.bpm.map(Double.init),
                        artworkID: track.coverArt ?? track.id,
                        artworkURL: artworkURL(for: track, in: album, size: 512),
                        url: try NavidromeConnection.streamURL(
                            address: serverAddress,
                            username: username,
                            password: password,
                            trackID: track.id,
                            maxBitRate: selectedStreamBitRate
                        )
                    )
                }
                startingTrackID = queue.first?.id
                nowPlaying.setShuffleEnabled(false)
                try await nowPlaying.start(queue: queue, at: 0)
                playbackMessage = "BreeMusic Radio"
                #else
                if let track = randomTracks.first {
                    let streamURL = try NavidromeConnection.streamURL(address: serverAddress, username: username, password: password, trackID: track.id, maxBitRate: selectedStreamBitRate)
                    player?.pause()
                    player = AVPlayer(url: streamURL)
                    currentTrackID = track.id
                    isPaused = false
                    playbackMessage = track.title
                    player?.play()
                }
                #endif
            } catch {
                playbackMessage = "Could not start BreeMusic Radio: \(error.localizedDescription)"
            }
        }
    }

    private func playFromHistory(_ item: MostPlayedTrackRecord) {
        selectedAlbum = item.album
        showingAlbumDetail = false
        tracks = []
        isLoadingTracks = true
        trackLoadError = nil
        Task {
            do {
                let loadedTracks = try await NavidromeConnection.loadTracks(
                    address: serverAddress,
                    username: username,
                    password: password,
                    albumID: item.album.id
                )
                guard selectedAlbum?.id == item.album.id else { return }
                tracks = loadedTracks
                for track in loadedTracks { albumByTrackID[track.id] = item.album }
                isLoadingTracks = false
                if let track = loadedTracks.first(where: { $0.id == item.track.id }) {
                    play(track)
                } else {
                    playbackMessage = "That track is no longer in the Navidrome library."
                }
            } catch {
                guard selectedAlbum?.id == item.album.id else { return }
                isLoadingTracks = false
                playbackMessage = "Could not load the saved track: \(error.localizedDescription)"
            }
        }
    }

    private func recordPlayed(_ queuedTrack: BreeQueuedTrack, in album: NavidromeAlbum) {
        let track = NavidromeTrack(
            id: queuedTrack.id,
            title: queuedTrack.title,
            artist: queuedTrack.artist ?? "Unknown artist",
            track: nil,
            duration: Int(queuedTrack.duration),
            coverArt: queuedTrack.artworkID,
            bpm: queuedTrack.bpm.map(Int.init)
        )
        listeningHistory.append(ListeningHistoryEvent(
            id: UUID(),
            trackID: queuedTrack.id,
            trackTitle: queuedTrack.title,
            artist: queuedTrack.artist ?? "Unknown artist",
            album: album.name,
            duration: queuedTrack.duration,
            date: Date()
        ))
        listeningHistory = Array(listeningHistory.suffix(5000))
        if let historyData = try? JSONEncoder().encode(listeningHistory) {
            UserDefaults.standard.set(historyData, forKey: "BreeMusic.ListeningHistory")
        }
        if let index = mostPlayed.firstIndex(where: { $0.track.id == track.id }) {
            mostPlayed[index].playCount += 1
        } else {
            mostPlayed.append(MostPlayedTrackRecord(track: track, album: album, playCount: 1))
        }
        mostPlayed.sort { $0.playCount == $1.playCount ? $0.track.title.localizedStandardCompare($1.track.title) == .orderedAscending : $0.playCount > $1.playCount }
        mostPlayed = Array(mostPlayed.prefix(100))
        if let data = try? JSONEncoder().encode(mostPlayed) {
            UserDefaults.standard.set(data, forKey: "BreeMusic.MostPlayed")
        }
    }

    private var recentlyPlayedItems: [RecentlyPlayedHomeItem] {
        var items: [RecentlyPlayedHomeItem] = []
        var seenTrackIDs = Set<String>()
        for event in listeningHistory.sorted(by: { $0.date > $1.date }) {
            guard let record = mostPlayed.first(where: { candidate in
                if let trackID = event.trackID { return candidate.track.id == trackID }
                return candidate.track.title == event.trackTitle
                    && (candidate.track.artist ?? "Unknown artist") == event.artist
                    && candidate.album.name == event.album
            }), seenTrackIDs.insert(record.track.id).inserted else { continue }
            items.append(RecentlyPlayedHomeItem(id: "track-\(record.track.id)", title: record.track.title, date: event.date, track: record, album: nil, mixName: nil))
        }
        var seenAlbumIDs = Set<String>()
        for opened in recentOpenedAlbums.sorted(by: { $0.date > $1.date }) where seenAlbumIDs.insert(opened.album.id).inserted {
            items.append(RecentlyPlayedHomeItem(id: "album-\(opened.album.id)", title: opened.album.name, date: opened.date, track: nil, album: opened.album, mixName: nil))
        }
        return Array(items.sorted { $0.date > $1.date }.prefix(8))
    }

    private func recordRecentMix(_ name: String) {
        recentMixHistory.append(RecentMixPlayback(name: name, date: Date()))
        recentMixHistory = Array(recentMixHistory.suffix(100))
        if let data = try? JSONEncoder().encode(recentMixHistory) {
            UserDefaults.standard.set(data, forKey: "BreeMusic.RecentMixHistory")
        }
    }

    private func toggleFavorite(_ trackID: String) {
        if favoriteTrackIDs.contains(trackID) {
            favoriteTrackIDs.remove(trackID)
        } else {
            favoriteTrackIDs.insert(trackID)
        }
        UserDefaults.standard.set(favoriteTrackIDs.sorted(), forKey: "BreeMusic.Favorites")
    }

    private func toggleReaction(_ trackID: String, liked: Bool) {
        if liked {
            if likedTrackIDs.contains(trackID) {
                likedTrackIDs.remove(trackID)
            } else {
                likedTrackIDs.insert(trackID)
                dislikedTrackIDs.remove(trackID)
            }
        } else if dislikedTrackIDs.contains(trackID) {
            dislikedTrackIDs.remove(trackID)
        } else {
            dislikedTrackIDs.insert(trackID)
            likedTrackIDs.remove(trackID)
        }
        UserDefaults.standard.set(likedTrackIDs.sorted(), forKey: "BreeMusic.Likes")
        UserDefaults.standard.set(dislikedTrackIDs.sorted(), forKey: "BreeMusic.Dislikes")
    }

    private func play(_ track: NavidromeTrack, opensNowPlaying: Bool = true) {
        guard startingTrackID != track.id else { return }
        if currentTrackID == track.id {
            if opensNowPlaying { showingNowPlaying = true }
            #if os(iOS)
            let currentlyPlaying = nowPlaying.isPlaying
            #else
            let currentlyPlaying = !isPaused
            #endif
            if currentlyPlaying {
                #if os(iOS)
                nowPlaying.pause()
                #else
                player?.pause()
                #endif
                isPaused = true
                playbackMessage = "Paused · \(track.title)"
            } else {
                #if os(iOS)
                nowPlaying.resume()
                #else
                player?.play()
                #endif
                isPaused = false
                playbackMessage = track.title
            }
            return
        }

        #if os(iOS)
        BreeEQSettings.shared.setMixProfile(nil)
        #endif
        activeMoodMix = nil
        activeGenre = nil

        #if os(iOS)
        do {
            guard let selectedAlbum else { return }
            let playbackQueue = try tracks.map { queuedTrack in
                BreeQueuedTrack(
                    id: queuedTrack.id,
                    title: queuedTrack.title,
                    artist: queuedTrack.artist ?? selectedAlbum.artist,
                    album: selectedAlbum.name,
                    duration: TimeInterval(queuedTrack.duration ?? 0),
                    bpm: queuedTrack.bpm.map(Double.init),
                    artworkID: queuedTrack.coverArt ?? selectedAlbum.coverArt ?? queuedTrack.id,
                    artworkURL: artworkURL(for: queuedTrack, in: selectedAlbum, size: 512),
                    url: try NavidromeConnection.streamURL(
                        address: serverAddress,
                        username: username,
                        password: password,
                        trackID: queuedTrack.id,
                        maxBitRate: selectedStreamBitRate
                    )
                )
            }
            guard let queueIndex = playbackQueue.firstIndex(where: { $0.id == track.id }) else { return }

            startingTrackID = track.id
            openPlayerAfterTrackStarts = opensNowPlaying
            Task {
                defer {
                    if startingTrackID == track.id { startingTrackID = nil }
                }
                do {
                    nowPlaying.setShuffleEnabled(false)
                    try await nowPlaying.start(queue: playbackQueue, at: queueIndex)
                } catch {
                    openPlayerAfterTrackStarts = false
                    playbackMessage = "Could not play \(track.title): \(error.localizedDescription)"
                }
            }
        } catch {
            playbackMessage = "Could not play \(track.title): \(error.localizedDescription)"
        }
        #else
        do {
            let streamURL = try NavidromeConnection.streamURL(
                address: serverAddress,
                username: username,
                password: password,
                trackID: track.id,
                maxBitRate: selectedStreamBitRate
            )
            let nextPlayer = AVPlayer(url: streamURL)
            player?.pause()
            player = nextPlayer
            currentTrackID = track.id
            isPaused = false
            playbackMessage = track.title
            nextPlayer.play()
        } catch {
            playbackMessage = "Could not play \(track.title): \(error.localizedDescription)"
        }
        #endif
    }

    private func stopPlayback() {
        #if os(iOS)
        BreeEQSettings.shared.setMixProfile(nil)
        nowPlaying.stop()
        #else
        player?.pause()
        player = nil
        #endif
        currentTrackID = nil
        isPaused = false
        playbackMessage = nil
        activeMoodMix = nil
        activeGenre = nil
    }

    private static func durationLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func artworkURL(for track: NavidromeTrack, in album: NavidromeAlbum, size: Int = 160) -> URL? {
        let artworkID = track.coverArt ?? album.coverArt ?? track.id
        return try? NavidromeConnection.coverArtURL(
            address: serverAddress,
            username: username,
            password: password,
            artworkID: artworkID,
            size: size
        )
    }

    private func togglePlaybackFromPlayer() {
        guard currentTrackID != nil else { return }
        if isPaused {
            #if os(iOS)
            nowPlaying.resume()
            #else
            player?.play()
            #endif
            isPaused = false
            playbackMessage = tracks.first(where: { $0.id == currentTrackID })?.title
        } else {
            #if os(iOS)
            nowPlaying.pause()
            #else
            player?.pause()
            #endif
            isPaused = true
            let title = tracks.first(where: { $0.id == currentTrackID })?.title ?? "Now Playing"
            playbackMessage = "Paused · \(title)"
        }
    }

    private func skipTrack(by offset: Int) {
        guard let currentIndex = tracks.firstIndex(where: { $0.id == currentTrackID }) else { return }
        let targetIndex = currentIndex + offset
        guard tracks.indices.contains(targetIndex) else { return }
        play(tracks[targetIndex])
    }

    private func skipCurrentQueue(by offset: Int) {
        #if os(iOS)
        Task {
            do {
                if offset < 0 { try await nowPlaying.previousTrack() }
                else { try await nowPlaying.nextTrack() }
            } catch {
                playbackMessage = "Could not change track: \(error.localizedDescription)"
            }
        }
        #else
        skipTrack(by: offset)
        #endif
    }
}

@MainActor
private enum ArtworkImageCache {
    static let images = NSCache<NSURL, PlatformArtworkImage>()

    static func image(for url: URL) async -> PlatformArtworkImage? {
        let key = url as NSURL
        if let cached = images.object(forKey: key) { return cached }

        let fileURL = diskURL(for: url)
        if let data = try? Data(contentsOf: fileURL), let image = PlatformArtworkImage(data: data) {
            images.setObject(image, forKey: key)
            return image
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let image = PlatformArtworkImage(data: data) else { return nil }
            images.setObject(image, forKey: key)
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
            return image
        } catch {
            return nil
        }
    }

    static func preload(urls: [URL]) async {
        var seen = Set<String>()
        let uniqueURLs = urls.filter { seen.insert($0.absoluteString).inserted }
        for start in stride(from: 0, to: uniqueURLs.count, by: 8) {
            let batch = Array(uniqueURLs[start..<min(start + 8, uniqueURLs.count)])
            await withTaskGroup(of: Void.self) { group in
                for url in batch {
                    group.addTask { _ = await image(for: url) }
                }
            }
        }
    }

    private static func diskURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BreeMusicArtwork", isDirectory: true)
            .appendingPathComponent(digest + ".image")
    }
}

private struct CachedArtworkView<Placeholder: View>: View {
    let url: URL
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var artwork: PlatformArtworkImage?

    init(url: URL, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        _artwork = State(initialValue: ArtworkImageCache.images.object(forKey: url as NSURL))
    }

    var body: some View {
        Group {
            if let artwork {
                platformImage(artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            if let loadedImage = await ArtworkImageCache.image(for: url) {
                artwork = loadedImage
            }
        }
        .onChange(of: url) { _, newURL in
            if let cached = ArtworkImageCache.images.object(forKey: newURL as NSURL) {
                artwork = cached
            }
        }
    }

    private func platformImage(_ image: PlatformArtworkImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}

private struct MovingTickerText: View {
    let text: String
    let font: Font

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

private struct TrackArtwork: View {
    let url: URL?
    var onTap: (() -> Void)? = nil
    @State private var artwork: PlatformArtworkImage?

    var body: some View {
        Group {
            if let artwork {
                platformImage(artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.gray.opacity(0.22))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { onTap?() }
        .accessibilityElement()
        .accessibilityLabel("Album artwork")
        .accessibilityHint("Tap to open the player when available.")
        .task(id: url) {
            guard let url else {
                artwork = nil
                return
            }
            if let loadedImage = await ArtworkImageCache.image(for: url) {
                artwork = loadedImage
            }
        }
    }

    private func platformImage(_ image: PlatformArtworkImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}

#if os(iOS)
private struct NowPlayingAlbumArt: View {
    let artworkURL: URL?

    var body: some View {
        TrackArtwork(url: artworkURL)
    }
}

private struct NowPlayingAtmosphere: View {
    let artworkURL: URL?
    @State private var pixelatedArtwork: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let pixelatedArtwork {
                    Image(uiImage: pixelatedArtwork)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 3)

                    Image(uiImage: pixelatedArtwork)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(1.18)
                        .blur(radius: 24)
                        .offset(x: 28, y: -8)
                        .opacity(0.72)

                    Image(uiImage: pixelatedArtwork)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(1.24)
                        .blur(radius: 34)
                        .offset(x: -34, y: 12)
                        .opacity(0.42)
                } else {
                    BreeHomePalette.surface
                }

                LinearGradient(
                    colors: [BreeHomePalette.surface.opacity(0.30), BreeHomePalette.surface.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: artworkURL) {
            guard let artworkURL,
                  let source = await ArtworkImageCache.image(for: artworkURL) else {
                pixelatedArtwork = nil
                return
            }
            let targetSize = CGSize(width: 48, height: 48)
            pixelatedArtwork = UIGraphicsImageRenderer(size: targetSize).image { _ in
                source.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }
    }
}

private struct MusicSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var appearanceThemeRaw: String
    @Binding var streamQualityRaw: String
    let connectionQuality: String
    @Binding var crossfadeEnabled: Bool
    @Binding var crossfadeDuration: Double
    @Binding var transitionCurve: BreeTransitionCurve
    @Binding var beatSyncEnabled: Bool
    let onOpenProfile: () -> Void
    let onOpenEqualizer: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("BreeMusic") {
                    Button(action: onOpenProfile) {
                        Label("Profile and login", systemImage: "person.crop.circle")
                    }
                    Button(action: onOpenEqualizer) {
                        Label("Equalizer and DSP", systemImage: "slider.horizontal.3")
                    }
                }
                Section("Appearance") {
                    Picker("Color theme", selection: $appearanceThemeRaw) {
                        ForEach(BreeAppearanceTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    .tint(BreeHomePalette.lightOrange)
                    Text("Your selected colors apply across BreeMusic and are saved on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Streaming quality") {
                    Picker("Audio quality", selection: $streamQualityRaw) {
                        ForEach(BreeStreamQuality.allCases) { quality in
                            Text(quality.title).tag(quality.rawValue)
                        }
                    }
                    .tint(BreeHomePalette.lightOrange)
                    Text(streamQualityDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Current connection: \(connectionQuality). Compressed streams use MP3 at the selected bitrate. Navidrome transcodes the stream; your original music files stay unchanged.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Playback") {
                    Toggle("Crossfade between tracks", isOn: $crossfadeEnabled)
                    if crossfadeEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Overlap")
                                Spacer()
                                Text("\(crossfadeDuration, specifier: "%.1f") sec")
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $crossfadeDuration, in: 1...12, step: 0.5)
                                .tint(BreeHomePalette.lightOrange)
                            Picker("Transition", selection: $transitionCurve) {
                                ForEach(BreeTransitionCurve.allCases) { curve in
                                    Text(curve.title).tag(curve)
                                }
                            }
                            .pickerStyle(.segmented)
                            TransitionCurvePreview(curve: transitionCurve)
                                .frame(height: 52)
                            Toggle("Align fades to the beat", isOn: $beatSyncEnabled)
                            Text("The next track fades in while the current track fades out.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Beat alignment uses BPM tags when both tracks have similar tempos; otherwise the regular fade starts on time.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private var streamQualityDescription: String {
        switch BreeStreamQuality(rawValue: streamQualityRaw) ?? .automatic {
        case .automatic:
            "Automatic starts at 96 kbps on cellular or constrained links and 160 kbps on Wi-Fi. If playback stalls, it retries progressively lower, down to 64 kbps."
        case .dataSaver:
            "Uses 64 kbps to reduce bandwidth on slow or limited connections."
        case .standard:
            "Uses 128 kbps for a balance of sound quality and bandwidth."
        case .high:
            "Requests up to 320 kbps when your connection can keep up."
        case .original:
            "Requests the source file without a bitrate limit; this uses the most bandwidth."
        }
    }
}

#if os(iOS)
private struct BreeAudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(BreeHomePalette.lightOrange)
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        picker.tintColor = .white
        picker.activeTintColor = UIColor(BreeHomePalette.lightOrange)
    }
}
#endif

private struct NowPlayingDetailView: View {
    let title: String
    let artist: String
    let metadata: NavidromeTrack?
    let playbackError: String?
    let artworkURL: URL?
    let isPlaying: Bool
    let isFavorite: Bool
    let isLiked: Bool
    let isDisliked: Bool
    let repeatMode: BreeRepeatMode
    let isShuffleEnabled: Bool
    @Binding var showingLyrics: Bool
    let lyrics: [BreeLyricLine]
    let lyricSearchTargetLineID: Int?
    let isLoadingLyrics: Bool
    let elapsedTime: TimeInterval
    let duration: TimeInterval
    let onEqualizer: () -> Void
    let onDismiss: () -> Void
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onRepeatModeChange: () -> Void
    let onShuffleToggle: () -> Void
    let onFavoriteToggle: () -> Void
    let onLikeToggle: () -> Void
    let onDislikeToggle: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onArtistSelected: (String) -> Void

    @State private var showingMetadata = false
    @State private var downwardDragOffset: CGFloat = 0

    private var selectedClearGlassCircle: some View {
        Circle()
            .fill(BreeHomePalette.glassTint.opacity(0.32))
            .glassEffect(.regular.tint(BreeHomePalette.glassTint.opacity(0.42)).interactive(), in: Circle())
    }

    var body: some View {
        GeometryReader { geometry in
            let artworkSide = max(0, min(geometry.size.width - 72, geometry.size.height * 0.43))
            ZStack {
                NowPlayingAtmosphere(artworkURL: artworkURL)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Button(action: onDismiss) {
                            Image(systemName: "chevron.down")
                                .font(.headline.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial.opacity(0.28), in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to homepage")
                        Spacer()
                        VStack(spacing: 3) {
                            Text("NOW PLAYING")
                                .font(.caption2.bold())
                                .tracking(1.4)
                            Text("BreeMusic")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        BreeAudioRoutePicker()
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial.opacity(0.22), in: Circle())
                        Button(action: onEqualizer) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 42, height: 42)
                                .background(.ultraThinMaterial.opacity(0.28), in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open equalizer")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)

                    Spacer(minLength: 20)

                    if showingLyrics {
                        lyricsPanel
                            .frame(maxWidth: 520)
                            .frame(maxHeight: geometry.size.height * 0.52)
                            .padding(.horizontal, 28)
                    } else if showingMetadata {
                        metadataPanel
                            .frame(maxWidth: 520)
                            .frame(maxHeight: geometry.size.height * 0.52)
                            .padding(.horizontal, 28)
                    } else {
                        NowPlayingAlbumArt(artworkURL: artworkURL)
                        .frame(width: artworkSide, height: artworkSide)
                    }

                    Spacer(minLength: 24)

                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(title)
                                .font(.title2.bold())
                                .lineLimit(1)
                            Button { onArtistSelected(artist) } label: {
                                Text(artist)
                                    .font(.title3)
                                    .foregroundStyle(BreeHomePalette.lightOrange.opacity(0.92))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            if let playbackError {
                                Text("Playback failed: \(playbackError)")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.95))
                                    .lineLimit(2)
                                    .accessibilityLabel("Playback failed. \(playbackError)")
                            }
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showingLyrics.toggle()
                                    showingMetadata = false
                                }
                            } label: {
                                Image(systemName: showingLyrics ? "circle.lefthalf.filled" : "quote.bubble")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 42, height: 42)
                                    .background {
                                        if showingLyrics { selectedClearGlassCircle }
                                        else { Circle().fill(.ultraThinMaterial.opacity(0.22)) }
                                    }
                                    .clipShape(Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showingLyrics ? "Show album cover" : "Show lyrics")
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showingMetadata.toggle()
                                    showingLyrics = false
                                }
                            } label: {
                                Image(systemName: showingMetadata ? "circle.lefthalf.filled" : "info.circle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 42, height: 42)
                                    .background {
                                        if showingMetadata { selectedClearGlassCircle }
                                        else { Circle().fill(.ultraThinMaterial.opacity(0.22)) }
                                    }
                                    .clipShape(Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showingMetadata ? "Show album cover" : "Show track information")
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 22)

                    PlaybackScrubber(
                        elapsedTime: elapsedTime,
                        duration: duration,
                        onSeek: onSeek,
                        tint: .white,
                        labelOpacity: 0.7
                    )
                    .padding(.horizontal, 26)

                    HStack(spacing: 28) {
                        feedbackButton(symbol: "hand.thumbsup.fill", isSelected: isLiked, label: isLiked ? "Unlike track" : "Like track", action: onLikeToggle)
                        feedbackButton(symbol: "hand.thumbsdown.fill", isSelected: isDisliked, label: isDisliked ? "Remove dislike" : "Dislike track", action: onDislikeToggle)
                        feedbackButton(symbol: isFavorite ? "star.fill" : "star", isSelected: isFavorite, label: isFavorite ? "Remove favorite" : "Add favorite", action: onFavoriteToggle)
                    }
                    .padding(.top, 12)

                    HStack(spacing: 50) {
                        Button(action: onPrevious) {
                            Image(systemName: "backward.end.fill").font(.title2)
                                .frame(width: 52, height: 52)
                                .background(.ultraThinMaterial.opacity(0.22), in: Circle())
                        }
                        Button(action: onPlayPause) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2.bold())
                                .frame(width: 72, height: 72)
                                .background(.ultraThinMaterial.opacity(isPlaying ? 0.30 : 0.20), in: Circle())
                                .foregroundStyle(.white)
                        }
                        Button(action: onNext) {
                            Image(systemName: "forward.end.fill").font(.title2)
                                .frame(width: 52, height: 52)
                                .background(.ultraThinMaterial.opacity(0.22), in: Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)
                    HStack(spacing: 14) {
                        Button(action: onRepeatModeChange) {
                            Label(repeatMode.title, systemImage: repeatMode.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(repeatMode == .off ? .white.opacity(0.72) : BreeHomePalette.lightOrange)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background {
                                    if repeatMode != .off {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(BreeHomePalette.glassTint.opacity(0.48))
                                            .glassEffect(.regular.tint(BreeHomePalette.glassTint.opacity(0.55)).interactive(), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(repeatMode.title). Tap to change repeat mode.")

                        Button(action: onShuffleToggle) {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isShuffleEnabled ? BreeHomePalette.lightOrange : .white.opacity(0.72))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background {
                                    if isShuffleEnabled {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(BreeHomePalette.glassTint.opacity(0.48))
                                            .glassEffect(.regular.tint(BreeHomePalette.glassTint.opacity(0.55)).interactive(), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isShuffleEnabled ? "Turn shuffle off" : "Turn shuffle on")
                    }
                    .padding(.top, 15)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 22))
                }
                .foregroundStyle(.white)
            }
            .preferredColorScheme(.dark)
            .background(.clear)
            .contentShape(Rectangle())
            .offset(y: max(0, downwardDragOffset))
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard value.translation.height > 0,
                              abs(value.translation.width) < abs(value.translation.height) * 0.7 else { return }
                        downwardDragOffset = value.translation.height
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) < abs(value.translation.height) * 0.7 else {
                            downwardDragOffset = 0
                            return
                        }
                        if value.translation.height > 130 {
                            onDismiss()
                        } else {
                            withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
                                downwardDragOffset = 0
                            }
                        }
                    }
            )
        }
    }

    private var metadataPanel: some View {
        ScrollView {
            if let metadata {
                let trackArtistLabel = metadata.displayArtist ?? metadata.artists?.map(\.name).joined(separator: ", ") ?? metadata.artist ?? ""
                let albumArtistLabel = metadata.displayAlbumArtist ?? metadata.albumArtists?.map(\.name).joined(separator: ", ") ?? ""
                let artistRows: [(String, String)] = [
                    ("Track artist", trackArtistLabel),
                    ("Album artist", albumArtistLabel),
                    ("Composer", metadata.displayComposer ?? "")
                ]
                let contributorRows = (metadata.contributors ?? []).map { contributor in
                    let role = contributor.role.replacingOccurrences(of: "_", with: " ").capitalized
                    let subRole = contributor.subRole.map { " · \($0)" } ?? ""
                    return ("\(role)\(subRole)", contributor.artist.name)
                }
                let yearLabel: String = metadata.year.map { String($0) } ?? ""
                let genreLabel: String = metadata.genres?.map(\.name).joined(separator: ", ") ?? metadata.genre ?? ""
                let groupingLabel = metadata.groupings?.joined(separator: ", ") ?? ""
                let basicRows: [(String, String)] = [
                    ("Album", metadata.album ?? ""),
                    ("Year", yearLabel),
                    ("Track / disc", trackAndDiscLabel(metadata)),
                    ("Genre", genreLabel),
                    ("Grouping", groupingLabel),
                    ("Comment", metadata.comment ?? ""),
                    ("Explicit content", metadata.explicitStatus?.capitalized ?? ""),
                    ("MusicBrainz ID", metadata.musicBrainzId ?? "")
                ]
                let channelLabel: String = metadata.channelCount.map { $0 == 1 ? "Mono" : "\($0)-channel" } ?? ""
                let tempoLabel: String = metadata.bpm.map { String($0) + " BPM" } ?? ""
                let bitrateLabel: String = metadata.bitRate.map { String($0) + " kbps" } ?? ""
                let durationLabel: String = metadata.duration.map { Self.durationLabel(TimeInterval($0)) } ?? ""
                let moodLabel: String = metadata.moods?.joined(separator: ", ") ?? ""
                let trackGainLabel: String = metadata.replayGain?.trackGain.map { String(format: "%+.1f dB", $0) } ?? ""
                let audioRows: [(String, String)] = [
                    ("Format", audioFormatLabel(metadata)),
                    ("Resolution", audioResolutionLabel(metadata)),
                    ("Bitrate", bitrateLabel),
                    ("Channels", channelLabel),
                    ("Duration", durationLabel),
                    ("Tempo", tempoLabel),
                    ("Mood", moodLabel),
                    ("Track gain", trackGainLabel)
                ]

                VStack(alignment: .leading, spacing: 12) {
                    metadataSection("ARTIST & CONTRIBUTOR ROLES", rows: artistRows + contributorRows)
                    metadataSection("BASIC & DESCRIPTIVE METADATA", rows: basicRows)
                    metadataSection("AUDIO & MOOD ANALYTICS", rows: audioRows)
                    if metadata.moods?.isEmpty != false && metadata.bpm == nil {
                        Text("Mood and tempo are shown when those tags are present in Navidrome.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.vertical, 8)
            } else {
                Text("Extended track metadata isn’t available for this song.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func metadataSection(_ title: String, rows: [(String, String)]) -> some View {
        let populatedRows = rows.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Group {
            if !populatedRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.caption2.weight(.bold))
                        .tracking(0.9)
                        .foregroundStyle(BreeHomePalette.lightOrange)
                    ForEach(Array(populatedRows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.0)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer(minLength: 8)
                            Text(row.1)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func trackAndDiscLabel(_ track: NavidromeTrack) -> String {
        let trackPart = track.track.map(String.init)
        let discPart = track.discNumber.map { "Disc \($0)" }
        return [discPart, trackPart.map { "Track \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    private func audioFormatLabel(_ track: NavidromeTrack) -> String {
        if let suffix = track.suffix, !suffix.isEmpty { return suffix.uppercased() }
        guard let contentType = track.contentType,
              let fileType = contentType.split(separator: "/").last else { return "" }
        return String(fileType).uppercased()
    }

    private func audioResolutionLabel(_ track: NavidromeTrack) -> String {
        let rate = track.samplingRate.map { String(format: "%.1f kHz", Double($0) / 1_000) }
        let depth = track.bitDepth.map { "\($0)-bit" }
        let parts = [rate, depth].compactMap { $0 }
        guard !parts.isEmpty else { return "" }
        let label: String
        if track.samplingRate == 44_100 && track.bitDepth == 16 {
            label = "CD quality"
        } else if (track.samplingRate ?? 0) > 44_100 || (track.bitDepth ?? 0) > 16 {
            label = "Hi-Res"
        } else {
            label = "Standard resolution"
        }
        return "\(label) · \(parts.joined(separator: " / "))"
    }

    private var lyricsPanel: some View {
        Group {
            if isLoadingLyrics {
                ProgressView("Loading lyrics…").tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lyrics.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(BreeHomePalette.lightOrange)
                    Text("No lyrics found for this track.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                syncedLyrics
            }
        }
        .padding(18)
    }

    private func feedbackButton(symbol: String, isSelected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(isSelected ? BreeHomePalette.lightOrange : .white.opacity(0.7))
                .frame(width: 42, height: 42)
                .background {
                    if isSelected { selectedClearGlassCircle }
                    else { Circle().fill(.ultraThinMaterial.opacity(0.20)) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var syncedLyrics: some View {
        let activeIndex = lyrics.lastIndex(where: { line in
            guard let startTime = line.startTime else { return false }
            return elapsedTime >= startTime
        })
        let highlightedLineID = lyricSearchTargetLineID ?? activeIndex

        return ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(lyrics) { line in
                        Button {
                            if let startTime = line.startTime { onSeek(startTime) }
                        } label: {
                            Text(line.text)
                                .font(.system(size: highlightedLineID == line.id ? 30 : 25, weight: highlightedLineID == line.id ? .bold : .semibold, design: .rounded))
                                .foregroundStyle(highlightedLineID == line.id ? .white : .white.opacity(line.startTime == nil ? 0.78 : 0.42))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .scaleEffect(highlightedLineID == line.id ? 1 : 0.98, anchor: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(line.startTime == nil)
                        .id(line.id)
                    }
                }
                .padding(.vertical, 100)
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .mask(LinearGradient(colors: [.clear, .black.opacity(0.8), .black, .black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
            .onChange(of: activeIndex) { _, index in
                guard lyricSearchTargetLineID == nil else { return }
                guard let index else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    scrollProxy.scrollTo(index, anchor: .center)
                }
            }
            .onChange(of: lyricSearchTargetLineID) { _, targetID in
                guard let targetID else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    scrollProxy.scrollTo(targetID, anchor: .center)
                }
            }
            .onAppear {
                if let lyricSearchTargetLineID {
                    scrollProxy.scrollTo(lyricSearchTargetLineID, anchor: .center)
                    return
                }
                guard let activeIndex else { return }
                scrollProxy.scrollTo(activeIndex, anchor: .center)
            }
        }
    }

    private static func durationLabel(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct ListeningRecapView: View {
    @Environment(\.dismiss) private var dismiss
    let events: [ListeningHistoryEvent]
    @State private var selectedYear = Calendar.current.component(.year, from: Date())

    private var years: [Int] {
        let available = Set(events.map { Calendar.current.component(.year, from: $0.date) })
        return available.union([Calendar.current.component(.year, from: Date())]).sorted(by: >)
    }
    private var yearEvents: [ListeningHistoryEvent] {
        events.filter { Calendar.current.component(.year, from: $0.date) == selectedYear }
    }
    private var topTracks: [(String, Int)] {
        Dictionary(grouping: yearEvents, by: \.trackTitle).map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }.prefix(10).map { $0 }
    }
    private var topArtists: [(String, Int)] {
        Dictionary(grouping: yearEvents, by: \.artist).map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }.prefix(5).map { $0 }
    }
    private var minutesListened: Int { Int(yearEvents.reduce(0) { $0 + $1.duration } / 60) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(years, id: \.self) { year in Text(String(year)).tag(year) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 10) {
                        recapStat("Tracks played", value: String(yearEvents.count), symbol: "music.note")
                        recapStat("Listening time", value: minutesListened < 60 ? "\(minutesListened)m" : "\(minutesListened / 60)h \(minutesListened % 60)m", symbol: "clock")
                    }
                    recapList(title: "Top artists", rows: topArtists)
                    recapList(title: "Most played tracks", rows: topTracks)
                    Text("BreeMusic starts collecting recap stats on this device from the day this feature is installed. It does not import Spotify Wrapped or Apple Music Replay data.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(18)
            }
            .background(BreeHomePalette.surface)
            .navigationTitle("Your Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func recapStat(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).foregroundStyle(BreeHomePalette.lightOrange).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func recapList(title: String, rows: [(String, Int)]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased()).font(.caption.bold()).tracking(1).foregroundStyle(BreeHomePalette.lightOrange)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
                        Text(row.0).font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text("\(row.1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }
        } else {
            ContentUnavailableView("No listening history yet", systemImage: "waveform", description: Text("Play some music in BreeMusic and your recap will grow over time."))
        }
    }
}

private struct PlaybackScrubber: View {
    let elapsedTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    let tint: Color
    let labelOpacity: Double
    @State private var draftValue: TimeInterval = 0
    @State private var isEditing = false

    private var displayedTime: TimeInterval { isEditing ? draftValue : elapsedTime }

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { draftValue = $0 }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        draftValue = elapsedTime
                        isEditing = true
                    } else {
                        onSeek(draftValue)
                        isEditing = false
                    }
                }
            )
            .tint(tint)
            .frame(height: 38)
            .contentShape(Rectangle())
            HStack {
                Text(Self.timeLabel(displayedTime))
                Spacer()
                Text(Self.timeLabel(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(labelOpacity))
        }
        .onAppear { draftValue = elapsedTime }
        .onChange(of: elapsedTime) { _, value in
            if !isEditing { draftValue = value }
        }
    }

    private static func timeLabel(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct TransitionCurvePreview: View {
    let curve: BreeTransitionCurve

    var body: some View {
        Canvas { context, size in
            for isIncoming in [false, true] {
                var path = Path()
                for step in 0...48 {
                    let progress = Double(step) / 48
                    let levels = curve.levels(at: progress)
                    let level = isIncoming ? levels.incoming : levels.outgoing
                    let point = CGPoint(x: size.width * progress, y: size.height * (1 - CGFloat(level)))
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(
                    path,
                    with: .color(isIncoming ? BreeHomePalette.lightOrange : BreeHomePalette.burntOrange.opacity(0.58)),
                    lineWidth: 2.5
                )
            }
        }
        .accessibilityLabel("Outgoing and incoming volume transition preview")
    }
}
#endif

#if os(iOS)
private typealias PlatformArtworkImage = UIImage
#else
private typealias PlatformArtworkImage = NSImage
#endif

private struct ConnectionResult {
    let isSuccess: Bool
    let title: String
    let detail: String

    var symbol: String { isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
}

#if os(iOS)
private enum SecureLoginStore {
    private static let service = "BreeMusic.NavidromeLogin"
    private static let account = "default"

    private struct Credentials: Codable {
        let username: String
        let password: String
    }

    static func save(username: String, password: String) throws {
        let data = try JSONEncoder().encode(Credentials(username: username, password: password))
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func load() -> (username: String, password: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else { return nil }
        return (credentials.username, credentials.password)
    }
}
#endif

private enum AlbumSortOrder {
    case album
    case artist
}

private struct NavidromeAlbum: Codable, Identifiable {
    let id: String
    let name: String
    let artist: String?
    let year: Int?
    let songCount: Int?
    let coverArt: String?
}

private struct NavidromeTrack: Codable, Identifiable {
    let id: String
    let title: String
    let artist: String?
    let track: Int?
    let duration: Int?
    let coverArt: String?
    let bpm: Int?
    var key: String? = nil
    var initialKey: String? = nil
    var album: String? = nil
    var albumId: String? = nil
    var year: Int? = nil
    var discNumber: Int? = nil
    var genre: String? = nil
    var suffix: String? = nil
    var contentType: String? = nil
    var bitRate: Int? = nil
    var bitDepth: Int? = nil
    var samplingRate: Int? = nil
    var channelCount: Int? = nil
    var comment: String? = nil
    var artists: [NavidromeArtistRecord]? = nil
    var displayArtist: String? = nil
    var albumArtists: [NavidromeArtistRecord]? = nil
    var displayAlbumArtist: String? = nil
    var contributors: [NavidromeContributor]? = nil
    var displayComposer: String? = nil
    var genres: [NavidromeGenre]? = nil
    var moods: [String]? = nil
    var groupings: [String]? = nil
    var musicBrainzId: String? = nil
    var explicitStatus: String? = nil
    var replayGain: NavidromeReplayGain? = nil
}

private struct BreeMoodMixCache: Codable {
    let updatedAt: Date
    let tracksByID: [String: NavidromeTrack]
    let trackIDsByMood: [String: [String]]
    var trackIDsByGenre: [String: [String]]? = nil

    var playlists: [String: [NavidromeTrack]] {
        trackIDsByMood.mapValues { ids in ids.compactMap { tracksByID[$0] } }
    }

    var genres: [String: [NavidromeTrack]] {
        (trackIDsByGenre ?? [:]).mapValues { ids in ids.compactMap { tracksByID[$0] } }
    }
}

private struct NavidromeSearchResults: Decodable {
    let songs: [NavidromeTrack]
    let albums: [NavidromeAlbum]
    let artists: [NavidromeArtistRecord]

    init(songs: [NavidromeTrack], albums: [NavidromeAlbum], artists: [NavidromeArtistRecord]) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
    }

    enum CodingKeys: String, CodingKey {
        case songs = "song"
        case albums = "album"
        case artists = "artist"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        songs = try container.decodeIfPresent([NavidromeTrack].self, forKey: .songs) ?? []
        albums = try container.decodeIfPresent([NavidromeAlbum].self, forKey: .albums) ?? []
        artists = try container.decodeIfPresent([NavidromeArtistRecord].self, forKey: .artists) ?? []
    }
}

#if os(iOS)
@MainActor
private final class BreeWeatherLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var temperatureLabel: String?
    @Published private(set) var conditionSymbol = "cloud.sun.fill"
    @Published private(set) var conditionDescription = "Current weather unavailable"

    private let locationManager = CLLocationManager()
    private var refreshTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refreshOnOpen() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        default:
            break
        }
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) }
                catch { return }
                guard let self else { return }
                if self.locationManager.authorizationStatus == .authorizedAlways || self.locationManager.authorizationStatus == .authorizedWhenInUse {
                    self.locationManager.requestLocation()
                }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { await loadTemperature(latitude: coordinate.latitude, longitude: coordinate.longitude) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { }

    private func loadTemperature(latitude: CLLocationDegrees, longitude: CLLocationDegrees) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "celsius")
        ]
        guard let url = components.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(BreeWeatherResponse.self, from: data)
            let celsius = response.current.temperature
            let value = Locale.current.measurementSystem == .us
                ? Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: .fahrenheit).value
                : celsius
            temperatureLabel = "\(Int(value.rounded()))°"
            conditionSymbol = Self.symbol(for: response.current.weatherCode)
            conditionDescription = Self.description(for: response.current.weatherCode)
        } catch {
            // Preserve the last successful reading when weather data is temporarily unavailable.
        }
    }

    private static func symbol(for code: Int) -> String {
        return switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85...86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.sun.fill"
        }
    }

    private static func description(for code: Int) -> String {
        return switch code {
        case 0: "Sunny"
        case 1: "Mostly sunny"
        case 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Foggy"
        case 51...57: "Drizzling"
        case 61...67, 80...82: "Raining"
        case 71...77, 85...86: "Snowing"
        case 95...99: "Thunderstorms"
        default: "Current weather"
        }
    }
}

private struct BreeWeatherResponse: Decodable {
    let current: Current
    struct Current: Decodable {
        let temperature: Double
        let weatherCode: Int
        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }
}
#endif

private struct ListeningHistoryEvent: Codable, Identifiable {
    let id: UUID
    let trackID: String?
    let trackTitle: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let date: Date
}

private struct PendingLyricsSearch {
    let trackID: String
    let query: String
}

private struct RecentAlbumOpen: Codable, Identifiable {
    let album: NavidromeAlbum
    let date: Date
    var id: String { album.id }
}

private struct ArtistRecentMedia: Identifiable {
    let id: String
    let title: String
    let date: Date
    let album: NavidromeAlbum?
    let track: MostPlayedTrackRecord?
}

private struct RecentMixPlayback: Codable, Identifiable {
    let name: String
    let date: Date
    var id: String { "mix-\(name)-\(date.timeIntervalSince1970)" }
}

private struct BreeLyricsSearchCache: Codable {
    let lyrics: [String: String]
    let keywordTrackIDs: [String: Set<String>]
}

private struct RecentlyPlayedHomeItem: Identifiable {
    let id: String
    let title: String
    let date: Date
    let track: MostPlayedTrackRecord?
    let album: NavidromeAlbum?
    let mixName: String?
}

private struct MostPlayedTrackRecord: Codable, Identifiable {
    let track: NavidromeTrack
    let album: NavidromeAlbum
    var playCount: Int
    var id: String { track.id }
}

private struct BreeLyricLine: Identifiable, Decodable, Equatable {
    let id: Int
    let startTime: TimeInterval?
    let text: String
}

private struct NavidromeLibrary {
    let serverVersion: String?
    let albums: [NavidromeAlbum]
}

private enum NavidromeConnection {
    static func checkServer(address: String, username: String, password: String) async throws {
        let response = try await request(
            address: address,
            endpoint: "ping.view",
            username: username,
            password: password
        )
        try check(response)
    }

    static func loadLibrary(address: String, username: String, password: String) async throws -> NavidromeLibrary {
        let ping = try await request(
            address: address,
            endpoint: "ping.view",
            username: username,
            password: password
        )
        try check(ping)

        let albumResponse = try await request(
            address: address,
            endpoint: "getAlbumList2.view",
            username: username,
            password: password,
            extraParameters: [
                URLQueryItem(name: "type", value: "alphabeticalByName"),
                URLQueryItem(name: "size", value: "500"),
                URLQueryItem(name: "offset", value: "0")
            ]
        )
        try check(albumResponse)

        return NavidromeLibrary(
            serverVersion: ping.serverVersion,
            albums: albumResponse.albumList2?.albums ?? []
        )
    }

    static func loadTracks(address: String, username: String, password: String, albumID: String) async throws -> [NavidromeTrack] {
        let response = try await request(
            address: address,
            endpoint: "getAlbum.view",
            username: username,
            password: password,
            extraParameters: [URLQueryItem(name: "id", value: albumID)]
        )
        try check(response)
        return response.album?.songs ?? []
    }

    static func createPlaylist(address: String, username: String, password: String, name: String, trackIDs: [String]) async throws {
        let parameters = [URLQueryItem(name: "name", value: name)] + trackIDs.map { URLQueryItem(name: "songId", value: $0) }
        let response = try await request(
            address: address,
            endpoint: "createPlaylist.view",
            username: username,
            password: password,
            extraParameters: parameters
        )
        try check(response)
    }

    static func loadRandomTracks(address: String, username: String, password: String, count: Int) async throws -> [NavidromeTrack] {
        let response = try await request(
            address: address,
            endpoint: "getRandomSongs.view",
            username: username,
            password: password,
            extraParameters: [URLQueryItem(name: "size", value: String(min(500, max(1, count))))]
        )
        try check(response)
        return response.randomSongs?.songs ?? []
    }

    static func search(address: String, username: String, password: String, query: String) async throws -> NavidromeSearchResults {
        let response = try await request(
            address: address,
            endpoint: "search3.view",
            username: username,
            password: password,
            extraParameters: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "songCount", value: "100"),
                URLQueryItem(name: "albumCount", value: "500"),
                URLQueryItem(name: "artistCount", value: "100")
            ]
        )
        try check(response)
        return response.searchResult3 ?? NavidromeSearchResults(songs: [], albums: [], artists: [])
    }

    static func loadArtists(address: String, username: String, password: String) async throws -> [NavidromeArtistRecord] {
        let directoryResponse = try await request(
            address: address,
            endpoint: "getArtists.view",
            username: username,
            password: password
        )
        try check(directoryResponse)
        return directoryResponse.artists?.indexes
            .flatMap(\.artists)
            ?? []
    }

    static func loadArtistInfo(address: String, username: String, password: String, artist: String) async throws -> NavidromeArtistInfo? {
        let matchingArtist = try await loadArtists(address: address, username: username, password: password)
            .first { $0.name.localizedCaseInsensitiveCompare(artist) == .orderedSame }
        guard let artistID = matchingArtist?.id else { return nil }
        return try await loadArtistInfo(address: address, username: username, password: password, artistID: artistID)
    }

    static func loadArtistInfo(address: String, username: String, password: String, artistID: String) async throws -> NavidromeArtistInfo? {
        let response = try await request(
            address: address,
            endpoint: "getArtistInfo2.view",
            username: username,
            password: password,
            extraParameters: [URLQueryItem(name: "id", value: artistID)]
        )
        try check(response)
        return response.artistInfo2 ?? response.artistInfo
    }

    static func loadAlbumInfo(address: String, username: String, password: String, albumID: String) async throws -> NavidromeAlbumInfo? {
        let response = try await request(
            address: address,
            endpoint: "getAlbumInfo2.view",
            username: username,
            password: password,
            extraParameters: [URLQueryItem(name: "id", value: albumID)]
        )
        try check(response)
        return response.albumInfo
    }

    static func loadLyrics(address: String, username: String, password: String, trackID: String, artist: String, title: String) async throws -> [BreeLyricLine] {
        do {
            let response = try await request(
                address: address,
                endpoint: "getLyricsBySongId.view",
                username: username,
                password: password,
                extraParameters: [
                    URLQueryItem(name: "id", value: trackID),
                    URLQueryItem(name: "enhanced", value: "true")
                ]
            )
            try check(response)
            if let structured = response.lyricsList?.structuredLyrics.first(where: { $0.synced && !$0.lines.isEmpty }) {
                let offset = TimeInterval(structured.offset ?? 0) / 1_000
                return structured.lines.enumerated().map { index, line in
                    BreeLyricLine(id: index, startTime: max(0, TimeInterval(line.start ?? 0) / 1_000 + offset), text: line.value)
                }
            }
            if let plain = response.lyricsList?.structuredLyrics.first(where: { !$0.lines.isEmpty }) {
                return plain.lines.enumerated().map { index, line in
                    BreeLyricLine(id: index, startTime: line.start.map { TimeInterval($0) / 1_000 }, text: line.value)
                }
            }
        } catch {
            // Older Navidrome versions do not expose the OpenSubsonic structured lyrics endpoint.
        }

        let response = try await request(
            address: address,
            endpoint: "getLyrics.view",
            username: username,
            password: password,
            extraParameters: [
                URLQueryItem(name: "artist", value: artist),
                URLQueryItem(name: "title", value: title)
            ]
        )
        try check(response)
        let value = response.lyrics?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return parseLyricsText(value)
    }

    private static func parseLyricsText(_ text: String) -> [BreeLyricLine] {
        let timestampPattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: timestampPattern) else { return [] }
        var result: [BreeLyricLine] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine as NSString
            let matches = regex.matches(in: rawLine, range: NSRange(location: 0, length: line.length))
            guard !matches.isEmpty else {
                let plain = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if !plain.isEmpty { result.append(BreeLyricLine(id: result.count, startTime: nil, text: plain)) }
                continue
            }
            let contentRange = NSRange(location: 0, length: line.length)
            let lyricText = regex.stringByReplacingMatches(in: rawLine, range: contentRange, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyricText.isEmpty else { continue }
            for match in matches {
                let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(line.substring(with: match.range(at: 2))) ?? 0
                let fractionText = match.range(at: 3).location == NSNotFound ? "" : line.substring(with: match.range(at: 3))
                let fractionScale: Double = fractionText.count == 1 ? 10 : (fractionText.count == 2 ? 100 : 1_000)
                let fraction = (Double(fractionText) ?? 0) / fractionScale
                result.append(BreeLyricLine(id: result.count, startTime: minutes * 60 + seconds + fraction, text: lyricText))
            }
        }
        return result.enumerated()
            .sorted { left, right in
                guard let leftTime = left.element.startTime, let rightTime = right.element.startTime else {
                    return left.offset < right.offset
                }
                return leftTime == rightTime ? left.offset < right.offset : leftTime < rightTime
            }
            .enumerated()
            .map { index, entry in BreeLyricLine(id: index, startTime: entry.element.startTime, text: entry.element.text) }
    }

    static func streamURL(address: String, username: String, password: String, trackID: String, maxBitRate: Int = 0) throws -> URL {
        var parameters = [URLQueryItem(name: "id", value: trackID)]
        if maxBitRate > 0 {
            parameters.append(URLQueryItem(name: "format", value: "mp3"))
            parameters.append(URLQueryItem(name: "maxBitRate", value: String(maxBitRate)))
        }
        return try makeURL(
            address: address,
            endpoint: "stream.view",
            username: username,
            password: password,
            extraParameters: parameters
        )
    }

    static func coverArtURL(address: String, username: String, password: String, artworkID: String, size: Int) throws -> URL {
        try makeURL(
            address: address,
            endpoint: "getCoverArt.view",
            username: username,
            password: password,
            authSalt: "breemusic-cover-art-v1",
            extraParameters: [
                URLQueryItem(name: "id", value: artworkID),
                URLQueryItem(name: "size", value: String(size))
            ]
        )
    }

    private static func request(
        address: String,
        endpoint: String,
        username: String,
        password: String,
        extraParameters: [URLQueryItem] = []
    ) async throws -> SubsonicResponse {
        let url = try makeURL(
            address: address,
            endpoint: endpoint,
            username: username,
            password: password,
            extraParameters: extraParameters
        )
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ConnectionError.timedOut
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ConnectionError.httpFailure
        }

        return try JSONDecoder().decode(SubsonicEnvelope.self, from: data).response
    }

    private static func makeURL(
        address: String,
        endpoint: String,
        username: String,
        password: String,
        authSalt: String? = nil,
        extraParameters: [URLQueryItem] = []
    ) throws -> URL {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedAddress),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host != nil else {
            throw ConnectionError.invalidAddress
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "rest", endpoint].filter { !$0.isEmpty }.joined(separator: "/")

        let salt = authSalt ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let digest = Insecure.MD5.hash(data: Data((password + salt).utf8))
        let token = digest.map { String(format: "%02x", $0) }.joined()
        components.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "BreeMusic"),
            URLQueryItem(name: "f", value: "json")
        ] + extraParameters

        guard let url = components.url else { throw ConnectionError.invalidAddress }
        return url
    }

    private static func check(_ response: SubsonicResponse) throws {
        guard response.status == "ok" else {
            throw ConnectionError.serverRejected(response.error?.message ?? "Check your username and password.")
        }
    }
}

private struct SubsonicEnvelope: Decodable {
    let response: SubsonicResponse

    enum CodingKeys: String, CodingKey {
        case response = "subsonic-response"
    }
}

private struct SubsonicResponse: Decodable {
    let status: String
    let serverVersion: String?
    let error: SubsonicError?
    let albumList2: AlbumListContainer?
    let album: AlbumDetails?
    let albumInfo: NavidromeAlbumInfo?
    let lyrics: LyricsDetails?
    let lyricsList: LyricsList?
    let artistInfo: NavidromeArtistInfo?
    let artistInfo2: NavidromeArtistInfo?
    let artists: ArtistIndexContainer?
    let searchResult3: NavidromeSearchResults?
    let randomSongs: RandomSongsContainer?
}

private struct ArtistIndexContainer: Decodable {
    let indexes: [ArtistIndex]

    enum CodingKeys: String, CodingKey { case indexes = "index" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        indexes = try container.decodeIfPresent([ArtistIndex].self, forKey: .indexes) ?? []
    }
}

private struct ArtistIndex: Decodable {
    let artists: [NavidromeArtistRecord]

    enum CodingKeys: String, CodingKey { case artists = "artist" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artists = try container.decodeIfPresent([NavidromeArtistRecord].self, forKey: .artists) ?? []
    }
}

private struct NavidromeArtistRecord: Codable, Identifiable {
    let id: String
    let name: String
}

private struct NavidromeContributor: Codable, Identifiable {
    let role: String
    let subRole: String?
    let artist: NavidromeArtistRecord
    var id: String { "\(role)-\(subRole ?? "")-\(artist.id)" }
}

private struct NavidromeGenre: Codable, Identifiable {
    let name: String
    var id: String { name }
}

private struct NavidromeReplayGain: Codable {
    let trackGain: Double?
    let albumGain: Double?
    let trackPeak: Double?
    let albumPeak: Double?
    let baseGain: Double?
}

private struct NavidromeArtistInfo: Decodable {
    let biography: String?
    let smallImageUrl: String?
    let mediumImageUrl: String?
    let largeImageUrl: String?

    func preferredImageURL(serverAddress: String) -> URL? {
        let serverHost = URLComponents(string: serverAddress)?.host
        for candidate in [largeImageUrl, mediumImageUrl, smallImageUrl].compactMap({ $0 }) {
            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || (scheme == "http" && url.host == serverHost) else { continue }
            return url
        }
        return nil
    }
}

private struct NavidromeAlbumInfo: Codable {
    let notes: String?
    let musicBrainzId: String?
    let lastFmUrl: String?

    var lastFmURL: String? { lastFmUrl }
}

private struct LyricsDetails: Decodable {
    let value: String?
}

private struct LyricsList: Decodable {
    let structuredLyrics: [StructuredLyrics]

    enum CodingKeys: String, CodingKey {
        case structuredLyrics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        structuredLyrics = try container.decodeIfPresent([StructuredLyrics].self, forKey: .structuredLyrics) ?? []
    }
}

private struct StructuredLyrics: Decodable {
    let synced: Bool
    let offset: Int?
    let lines: [StructuredLyricLine]

    enum CodingKeys: String, CodingKey {
        case synced
        case offset
        case lines = "line"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        synced = try container.decodeIfPresent(Bool.self, forKey: .synced) ?? false
        offset = try container.decodeIfPresent(Int.self, forKey: .offset)
        lines = try container.decodeIfPresent([StructuredLyricLine].self, forKey: .lines) ?? []
    }
}

private struct StructuredLyricLine: Decodable {
    let start: Int?
    let value: String
}

private struct RandomSongsContainer: Decodable {
    let songs: [NavidromeTrack]?
    enum CodingKeys: String, CodingKey { case songs = "song" }
}

private struct AlbumListContainer: Decodable {
    let albums: [NavidromeAlbum]?

    enum CodingKeys: String, CodingKey {
        case albums = "album"
    }
}

private struct AlbumDetails: Decodable {
    let songs: [NavidromeTrack]?

    enum CodingKeys: String, CodingKey {
        case songs = "song"
    }
}

private struct SubsonicError: Decodable {
    let message: String?
}

private enum ConnectionError: LocalizedError {
    case invalidAddress
    case httpFailure
    case timedOut
    case serverRejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Enter a server address such as http://your-navidrome-server:4533."
        case .httpFailure:
            return "The server returned an HTTP error. Check the address and Navidrome status."
        case .timedOut:
            return "Navidrome did not respond within 30 seconds. Check that the Windows PC is awake, Tailscale is connected on both devices, and Navidrome is running."
        case .serverRejected(let message):
            return message
        }
    }
}
