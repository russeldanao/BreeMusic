#if os(iOS)
import AVFoundation
import CoreMedia
import Foundation
import NowPlaying
import Observation

@Observable
@MainActor
final class BreeNowPlayingSession: MediaSessionRepresentable {
    nonisolated let id = UUID().uuidString

    private(set) var trackID: String?
    private(set) var title: String?
    private(set) var artist: String?
    private(set) var album: String?
    private(set) var isPlaying = false
    private(set) var playbackError: String?
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var timestamp = Date.now
    private(set) var queue: [BreeQueuedTrack] = []
    private(set) var currentQueueIndex: Int?
    private(set) var crossfadeEnabled: Bool
    private(set) var crossfadeDuration: Double
    private(set) var transitionCurve: BreeTransitionCurve
    private(set) var beatSyncEnabled: Bool
    private(set) var repeatMode: BreeRepeatMode
    private(set) var isShuffleEnabled: Bool
    private(set) var volume: Double

    var onTrackChanged: ((BreeQueuedTrack?) -> Void)?

    private var player: AVPlayer?
    private var itemStatusObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var playbackWaitTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var timeObserverPlayer: AVPlayer?
    private var mediaSession: MediaSession<BreeNowPlayingSession>?
    private var duration: TimeInterval = 0
    private var playbackGeneration: UInt64 = 0
    private var seekGeneration: UInt64 = 0
    private var isSeeking = false
    private var crossfadePlayer: AVPlayer?
    private var crossfadeTask: Task<Void, Never>?
    private var endNotificationObserver: NSObjectProtocol?
    private var handledEndTrackID: String?
    private var preparedNextPlayer: AVPlayer?
    private var preparedNextTrackID: String?
    private var preparedNextReady = false
    private var preparedNextStatusObservation: NSKeyValueObservation?
    private var originalQueue: [BreeQueuedTrack] = []
    private var isRepeatSeekInProgress = false
    private var playbackIntent = false
    private var adaptiveBitRateOverride: Int?
    private var dspBypassedForCurrentTrack = false
    @ObservationIgnored private var audioSessionObserverTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var routeRecoveryTask: Task<Void, Never>?

    init() {
        crossfadeEnabled = UserDefaults.standard.bool(forKey: "breeMusicCrossfadeEnabled")
        let savedDuration = UserDefaults.standard.double(forKey: "breeMusicCrossfadeDuration")
        crossfadeDuration = savedDuration == 0 ? 4 : min(12, max(1, savedDuration))
        transitionCurve = BreeTransitionCurve(rawValue: UserDefaults.standard.string(forKey: "breeMusicTransitionCurve") ?? "fade") ?? .fade
        beatSyncEnabled = UserDefaults.standard.bool(forKey: "breeMusicBeatSyncEnabled")
        repeatMode = BreeRepeatMode(rawValue: UserDefaults.standard.string(forKey: "breeMusicRepeatMode") ?? "off") ?? .off
        isShuffleEnabled = UserDefaults.standard.bool(forKey: "breeMusicShuffleEnabled")
        // The old fixed 90% limiter was persisted as the app's volume. Start
        // at full player output now that the cap has been removed.
        volume = 1
        UserDefaults.standard.set(volume, forKey: "breeMusicOutputVolume")
    }

    var trackDuration: TimeInterval { duration }

    var content: (any MediaContentRepresentable)? {
        guard let trackID, let title else { return nil }
        let currentTrack = currentQueueIndex.flatMap { queue.indices.contains($0) ? queue[$0] : nil }
        let trackArtist = currentTrack?.artist ?? artist ?? "Unknown artist"
        let trackAlbum = currentTrack?.album ?? album ?? ""

        guard let currentTrack, let artworkURL = currentTrack.artworkURL else {
            return MusicContent(
                id: trackID,
                songTitle: title,
                artistName: trackArtist,
                albumName: trackAlbum,
                type: .audio,
                duration: .finite(duration),
                artwork: nil
            )
        }

        let artworkID = currentTrack.artworkID
        let staticArtwork = Artwork(id: artworkID) { _ in
            let (data, _) = try await URLSession.shared.data(from: artworkURL)
            return try ArtworkRepresentation(data: data)
        }
        return MusicContent(
            id: trackID,
            songTitle: title,
            artistName: trackArtist,
            albumName: trackAlbum,
            type: .audio,
            duration: .finite(duration),
            artwork: staticArtwork
        )
    }

    var playbackSnapshot: MediaPlaybackSnapshot? {
        guard title != nil else { return nil }
        return MediaPlaybackSnapshot(
            state: isPlaying ? .playing() : .paused,
            elapsedTime: elapsedTime,
            timestamp: timestamp
        )
    }

    var commands: [MediaCommand] {
        [
            .play { self.resume() },
            .pause { self.pause() },
            .seekToPosition { seconds in self.seek(to: seconds) },
            .next { try await self.nextTrack() }.enabled(hasNextTrack),
            .previous { try await self.previousTrack() }.enabled(hasPreviousTrack)
        ]
    }

    func setShuffleEnabled(_ enabled: Bool) {
        guard enabled != isShuffleEnabled else { return }
        if let currentQueueIndex, queue.indices.contains(currentQueueIndex) {
            let currentTrack = queue[currentQueueIndex]
            if enabled {
                let alreadyPlayed = Array(queue.prefix(currentQueueIndex))
                let remaining = Array(queue.suffix(from: currentQueueIndex + 1)).shuffled()
                queue = alreadyPlayed + [currentTrack] + remaining
                self.currentQueueIndex = alreadyPlayed.count
            } else {
                queue = originalQueue
                self.currentQueueIndex = queue.firstIndex(where: { $0.id == currentTrack.id })
            }
            discardPreparedNextTrack()
            if let index = self.currentQueueIndex { prepareNextTrack(after: index) }
        }
        isShuffleEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "breeMusicShuffleEnabled")
    }

    func cycleRepeatMode() {
        let modes = BreeRepeatMode.allCases
        let nextIndex = (modes.firstIndex(of: repeatMode).map { $0 + 1 } ?? 0) % modes.count
        repeatMode = modes[nextIndex]
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "breeMusicRepeatMode")
        discardPreparedNextTrack()
        if let index = self.currentQueueIndex { prepareNextTrack(after: index) }
    }

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        UserDefaults.standard.set(volume, forKey: "breeMusicOutputVolume")
        player?.volume = Float(volume)
        crossfadePlayer?.volume = Float(volume)
    }

    func setCrossfadeEnabled(_ enabled: Bool) {
        crossfadeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "breeMusicCrossfadeEnabled")
        if !enabled { cancelCrossfade() }
    }

    func setCrossfadeDuration(_ seconds: Double) {
        crossfadeDuration = min(12, max(1, seconds))
        UserDefaults.standard.set(crossfadeDuration, forKey: "breeMusicCrossfadeDuration")
    }

    func setTransitionCurve(_ curve: BreeTransitionCurve) {
        transitionCurve = curve
        UserDefaults.standard.set(curve.rawValue, forKey: "breeMusicTransitionCurve")
    }

    func setBeatSyncEnabled(_ enabled: Bool) {
        beatSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "breeMusicBeatSyncEnabled")
    }

    private var hasNextTrack: Bool {
        guard let currentQueueIndex else { return false }
        return queueIndex(after: currentQueueIndex) != nil
    }

    private var hasPreviousTrack: Bool {
        guard let currentQueueIndex else { return false }
        return currentQueueIndex > 0 || repeatMode == .all && queue.count > 1
    }

    private func queueIndex(after index: Int) -> Int? {
        guard queue.indices.contains(index) else { return nil }
        if index + 1 < queue.count { return index + 1 }
        return repeatMode == .all && queue.count > 1 ? 0 : nil
    }

    func start(queue: [BreeQueuedTrack], at index: Int, preserveQueueOrder: Bool = false) async throws {
        guard queue.indices.contains(index) else { return }
        adaptiveBitRateOverride = nil
        originalQueue = queue
        self.queue = queue
        let startIndex: Int
        if isShuffleEnabled, queue.count > 1, !preserveQueueOrder {
            self.queue = [queue[index]] + queue.enumerated().filter { $0.offset != index }.map(\.element).shuffled()
            startIndex = 0
        } else {
            startIndex = index
        }
        try await playQueuedTrack(at: startIndex)
    }

    func nextTrack() async throws {
        guard let currentQueueIndex, let nextIndex = queueIndex(after: currentQueueIndex) else { return }
        try await playQueuedTrack(at: nextIndex)
    }

    func previousTrack() async throws {
        guard let currentQueueIndex else { return }
        if elapsedTime > 3 {
            isRepeatSeekInProgress = false
            seek(to: 0)
            player?.play()
            isPlaying = false
            timestamp = .now
            return
        }
        let previousIndex = currentQueueIndex > 0 ? currentQueueIndex - 1 : (repeatMode == .all && queue.count > 1 ? queue.count - 1 : nil)
        guard let previousIndex else {
            seek(to: 0)
            player?.play()
            isPlaying = false
            timestamp = .now
            return
        }
        try await playQueuedTrack(at: previousIndex)
    }

    private func playQueuedTrack(at index: Int, startingAt startTime: TimeInterval = 0) async throws {
        guard queue.indices.contains(index) else { return }
        observeAudioSessionChangesIfNeeded()
        playbackGeneration &+= 1
        let generation = playbackGeneration
        currentQueueIndex = index
        dspBypassedForCurrentTrack = false
        isRepeatSeekInProgress = false
        handledEndTrackID = nil
        let track = queue[index]
        let isNewSession = mediaSession == nil
        let preloadedPlayer = takePreparedNextPlayer(for: track.id)

        stopCurrentPlayer()
        playbackIntent = false
        playbackError = nil

        // Activate when starting the app's playback session. Re-activating on
        // every track can be rejected by iOS during a Bluetooth route handoff.
        if isNewSession {
            do {
                try await activatePlaybackAudioSession()
            } catch {
                throw BreePlaybackError.audioSessionActivationFailed(error.localizedDescription)
            }
        }

        self.trackID = track.id
        self.title = track.title
        self.artist = track.artist
        self.album = track.album
        self.duration = track.duration
        elapsedTime = max(0, startTime)
        timestamp = .now

        let newPlayer = preloadedPlayer ?? makePlayer(for: track)
        // A preloaded item may have been created while the prior track had
        // temporarily bypassed DSP. Reapply the current route's settings now.
        newPlayer.currentItem?.audioMix = isBluetoothOutputRoute ? nil : BreeEQSettings.shared.audioMix()
        newPlayer.volume = Float(volume)
        player = newPlayer
        if let item = newPlayer.currentItem {
            itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self, weak newPlayer] item, _ in
                guard item.status == .failed else { return }
                let message = item.error?.localizedDescription ?? "The audio stream failed to load."
                Task { @MainActor [weak self, weak newPlayer] in
                    guard let self, let newPlayer, self.player === newPlayer else { return }
                    self.playbackWaitTask?.cancel()
                    if await self.retryAtLowerBitRate(expectedPlayer: newPlayer) { return }
                    newPlayer.pause()
                    self.isPlaying = false
                    self.playbackError = message
                    self.timestamp = .now
                }
            }
            endNotificationObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { [weak self, weak newPlayer] _ in
                Task { @MainActor [weak self, weak newPlayer] in
                    guard let self, let newPlayer else { return }
                    self.handleTrackEnded(newPlayer, trackID: track.id)
                }
            }
        }

        playerStatusObservation = newPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self, weak newPlayer] observedPlayer, _ in
            let status = observedPlayer.timeControlStatus
            Task { @MainActor [weak self, weak newPlayer] in
                guard let self, let newPlayer, self.player === newPlayer else { return }
                switch status {
                case .playing:
                    self.playbackWaitTask?.cancel()
                    self.playbackWaitTask = nil
                    self.playbackError = nil
                    self.isPlaying = true
                    self.timestamp = .now
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = false
                    self.playbackWaitTask?.cancel()
                    self.playbackWaitTask = Task { @MainActor [weak self, weak newPlayer] in
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled,
                              let self,
                              let newPlayer,
                              self.player === newPlayer,
                              newPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
                        self.bypassDSPForCurrentTrack(on: newPlayer)
                        try? await Task.sleep(for: .seconds(6))
                        guard !Task.isCancelled,
                              self.player === newPlayer,
                              newPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
                        if await self.retryAtLowerBitRate(expectedPlayer: newPlayer) { return }
                        self.isPlaying = false
                        self.playbackError = self.playbackDiagnostic(for: newPlayer, reason: "The stream is still waiting after 8 seconds.")
                        self.timestamp = .now
                    }
                case .paused:
                    guard self.playbackIntent else {
                        self.isPlaying = false
                        self.timestamp = .now
                        return
                    }
                    self.isPlaying = false
                    self.playbackWaitTask?.cancel()
                    self.playbackWaitTask = Task { @MainActor [weak self, weak newPlayer] in
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled,
                              let self,
                              let newPlayer,
                              self.player === newPlayer,
                              self.playbackIntent,
                              newPlayer.timeControlStatus == .paused else { return }
                        self.bypassDSPForCurrentTrack(on: newPlayer)
                        try? await Task.sleep(for: .seconds(6))
                        guard !Task.isCancelled,
                              self.player === newPlayer,
                              self.playbackIntent,
                              newPlayer.timeControlStatus == .paused else { return }
                        if await self.retryAtLowerBitRate(expectedPlayer: newPlayer) { return }
                        self.playbackError = self.playbackDiagnostic(for: newPlayer, reason: "AVPlayer stayed paused after a play request.")
                        self.timestamp = .now
                    }
                    // AVPlayer can pause during the brief A2DP handoff even
                    // when the audio-session route notification is delayed.
                    self.scheduleBluetoothRouteRecovery()
                default:
                    break
                }
            }
        }

        installProgressObserver(on: newPlayer, trackID: track.id)
        if startTime > 0 {
            await newPlayer.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }
        playbackIntent = true
        isPlaying = false
        timestamp = .now
        newPlayer.play()
        scheduleBluetoothRouteRecovery()
        onTrackChanged?(track)
        prepareNextTrack(after: index)

        // Audio starts before awaiting Now Playing promotion so a slow system
        // session request cannot hold the first track in a non-playing state.
        if isNewSession {
            let session = MediaSession(self)
            mediaSession = session
            do {
                try await session.requestToBecomeApplicationPrimary()
                guard playbackGeneration == generation else { return }
                try await session.requestToBecomeSystemPrimary()
            } catch {
                print("Now Playing session promotion failed: \(error)")
            }
        }
    }

    private func observeAudioSessionChangesIfNeeded() {
        guard audioSessionObserverTokens.isEmpty else { return }
        let center = NotificationCenter.default
        let audioSession = AVAudioSession.sharedInstance()

        audioSessionObserverTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.refreshAudioMixForCurrentRoute()
                self.scheduleBluetoothRouteRecovery()
            }
        })

        if #available(iOS 27.0, *) {
            audioSessionObserverTokens.append(center.addObserver(
                forName: AVAudioSession.didBecomeInactiveNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.playbackIntent else { return }
                    self.isPlaying = false
                    self.timestamp = .now
                }
            })
            audioSessionObserverTokens.append(center.addObserver(
                forName: AVAudioSession.didBecomeActiveNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleBluetoothRouteRecovery() }
            })
            audioSessionObserverTokens.append(center.addObserver(
                forName: AVAudioSession.resumptionRecommendationNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                guard let context = notification.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext,
                      context.recommendation == .shouldResume else { return }
                Task { @MainActor [weak self] in self?.scheduleBluetoothRouteRecovery(reactivateSession: true) }
            })
        } else {
            audioSessionObserverTokens.append(center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                if type == .began {
                    Task { @MainActor [weak self] in
                        guard let self, self.playbackIntent else { return }
                        self.isPlaying = false
                        self.timestamp = .now
                    }
                } else if type == .ended,
                          let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                          AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
                    Task { @MainActor [weak self] in self?.scheduleBluetoothRouteRecovery() }
                }
            })
        }
    }

    private func activatePlaybackAudioSession() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        // The playback category routes to Bluetooth A2DP automatically.
        try audioSession.setCategory(.playback, mode: .default)
        do {
            if try await audioSession.activate(options: []) == false {
                try audioSession.setActive(true)
            }
        } catch {
            try audioSession.setActive(true)
        }
    }

    private func scheduleBluetoothRouteRecovery(reactivateSession: Bool = false) {
        guard playbackIntent, let expectedPlayer = player else { return }
        routeRecoveryTask?.cancel()
        routeRecoveryTask = Task { @MainActor [weak self, weak expectedPlayer] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled,
                  let self,
                  let expectedPlayer,
                  self.playbackIntent,
                  self.player === expectedPlayer else { return }
            do {
                if reactivateSession {
                    try await self.activatePlaybackAudioSession()
                }
                guard self.playbackIntent, self.player === expectedPlayer else { return }
                // Reissuing play is safe for an already-running AVPlayer and
                // helps head units that finish Bluetooth route negotiation
                // after the original play request.
                expectedPlayer.play()
                self.isPlaying = expectedPlayer.timeControlStatus == .playing
                if self.isPlaying { self.playbackError = nil }
                self.timestamp = .now
            } catch {
                self.playbackError = BreePlaybackError.audioSessionActivationFailed(error.localizedDescription).localizedDescription
                self.isPlaying = false
                self.timestamp = .now
            }
        }
    }

    private func reactivateAndResume(_ expectedPlayer: AVPlayer) {
        let generation = playbackGeneration
        Task { @MainActor [weak self, weak expectedPlayer] in
            guard let self, let expectedPlayer else { return }
            guard self.playbackIntent,
                  self.player === expectedPlayer,
                  self.playbackGeneration == generation else { return }
            expectedPlayer.play()
            self.isPlaying = expectedPlayer.timeControlStatus == .playing
            self.timestamp = .now
        }
    }

    private func playbackDiagnostic(for player: AVPlayer, reason: String) -> String {
        let route = AVAudioSession.sharedInstance().currentRoute.outputs
            .map(\.portName)
            .joined(separator: ", ")
        let output = route.isEmpty ? "no active audio output" : "output: \(route)"
        let itemError = player.currentItem?.error?.localizedDescription
        if let itemError, !itemError.isEmpty {
            return "\(reason) \(itemError) (\(output))"
        }
        return "\(reason) (\(output))"
    }

    private func retryAtLowerBitRate(expectedPlayer: AVPlayer) async -> Bool {
        guard playbackIntent,
              player === expectedPlayer,
              let index = currentQueueIndex,
              queue.indices.contains(index) else { return false }

        let requestedRate = URLComponents(url: queue[index].url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "maxBitRate" })
            .flatMap { Int($0.value ?? "") } ?? 0
        let currentRate = adaptiveBitRateOverride ?? requestedRate
        let lowerRate: Int
        switch currentRate {
        case 193...: lowerRate = 192
        case 129...192: lowerRate = 128
        case 97...128: lowerRate = 96
        case 65...96: lowerRate = 64
        default: return false
        }

        let currentTime = expectedPlayer.currentTime().seconds
        let resumeAt = currentTime.isFinite && currentTime > 0 ? currentTime : elapsedTime
        adaptiveBitRateOverride = lowerRate
        discardPreparedNextTrack()

        // Replacing a Navidrome stream mid-song can restart it at zero when
        // the transcoded response is not seekable. Keep this player alive;
        // apply the lower rate to the next track instead.
        guard resumeAt <= 1.5 else { return false }

        do {
            try await playQueuedTrack(at: index, startingAt: resumeAt)
            return true
        } catch {
            playbackError = "Could not retry at a lower stream quality: \(error.localizedDescription)"
            return false
        }
    }

    func resume() {
        player?.currentItem?.audioTimePitchAlgorithm = .timeDomain
        if let player,
           let itemDuration = player.currentItem?.duration.seconds,
           itemDuration.isFinite,
           itemDuration > 0,
           player.currentTime().seconds >= itemDuration - 0.5 {
            player.seek(to: .zero)
        }
        guard let player else { return }
        observeAudioSessionChangesIfNeeded()
        playbackIntent = true
        reactivateAndResume(player)
    }

    func pause() {
        playbackIntent = false
        routeRecoveryTask?.cancel()
        routeRecoveryTask = nil
        player?.currentItem?.audioTimePitchAlgorithm = .timeDomain
        cancelCrossfade()
        player?.pause()
        isPlaying = false
        timestamp = .now
    }

    func stop() {
        BreeEQSettings.shared.setMixProfile(nil)
        playbackIntent = false
        routeRecoveryTask?.cancel()
        routeRecoveryTask = nil
        playbackGeneration &+= 1
        stopCurrentPlayer()
        discardPreparedNextTrack()
        mediaSession = nil
        trackID = nil
        title = nil
        artist = nil
        album = nil
        elapsedTime = 0
        duration = 0
        isPlaying = false
        timestamp = .now
        queue = []
        originalQueue = []
        currentQueueIndex = nil
        onTrackChanged?(nil)
    }

    private func stopCurrentPlayer() {
        seekGeneration &+= 1
        isSeeking = false
        cancelCrossfade()
        playbackWaitTask?.cancel()
        playbackWaitTask = nil
        itemStatusObservation = nil
        playerStatusObservation = nil
        if let endNotificationObserver {
            NotificationCenter.default.removeObserver(endNotificationObserver)
            self.endNotificationObserver = nil
        }
        removeProgressObserver()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func removeProgressObserver() {
        if let timeObserver, let timeObserverPlayer {
            timeObserverPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeObserverPlayer = nil
    }

    private func makePlayer(for track: BreeQueuedTrack) -> AVPlayer {
        let sourceURL = adaptiveBitRateOverride.map { Self.url(track.url, withMaxBitRate: $0) } ?? track.url
        let item = AVPlayerItem(url: sourceURL)
        item.preferredForwardBufferDuration = 18
        item.audioMix = isBluetoothOutputRoute || dspBypassedForCurrentTrack ? nil : BreeEQSettings.shared.audioMix()
        let nextPlayer = AVPlayer(playerItem: item)
        nextPlayer.automaticallyWaitsToMinimizeStalling = true
        nextPlayer.networkResourcePriority = .high
        nextPlayer.volume = Float(volume)
        return nextPlayer
    }

    private static func url(_ url: URL, withMaxBitRate bitRate: Int) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var queryItems = components.queryItems ?? []
        if let index = queryItems.firstIndex(where: { $0.name == "maxBitRate" }) {
            queryItems[index].value = String(bitRate)
        } else {
            queryItems.append(URLQueryItem(name: "maxBitRate", value: String(bitRate)))
        }
        components.queryItems = queryItems
        return components.url ?? url
    }

    private var isBluetoothOutputRoute: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            output.portType == .bluetoothA2DP
                || output.portType == .bluetoothLE
                || output.portType == .bluetoothHFP
        }
    }

    private func refreshAudioMixForCurrentRoute() {
        let mix = isBluetoothOutputRoute || dspBypassedForCurrentTrack ? nil : BreeEQSettings.shared.audioMix()
        player?.currentItem?.audioMix = mix
        preparedNextPlayer?.currentItem?.audioMix = mix
    }

    private func bypassDSPForCurrentTrack(on expectedPlayer: AVPlayer) {
        guard player === expectedPlayer,
              !isBluetoothOutputRoute,
              expectedPlayer.currentItem?.audioMix != nil else { return }
        dspBypassedForCurrentTrack = true
        expectedPlayer.currentItem?.audioMix = nil
    }

    private func prepareNextTrack(after index: Int) {
        guard let nextIndex = queueIndex(after: index), queue.indices.contains(nextIndex) else {
            discardPreparedNextTrack()
            return
        }
        let track = queue[nextIndex]
        guard preparedNextTrackID != track.id else { return }
        discardPreparedNextTrack()

        let preloader = makePlayer(for: track)
        preloader.currentItem?.preferredForwardBufferDuration = 3
        preloader.volume = 0
        preloader.networkResourcePriority = .low
        preparedNextPlayer = preloader
        preparedNextTrackID = track.id
        guard let item = preloader.currentItem else { return }
        preparedNextStatusObservation = item.observe(\.status, options: [.new]) { [weak self, weak preloader] item, _ in
            guard item.status == .readyToPlay, let preloader else { return }
            preloader.preroll(atRate: 1) { [weak self, weak preloader] finished in
                Task { @MainActor [weak self, weak preloader] in
                    guard let self, let preloader, self.preparedNextPlayer === preloader else { return }
                    guard finished else {
                        self.discardPreparedNextTrack()
                        return
                    }
                    self.preparedNextReady = true
                    preloader.pause()
                    preloader.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
    }

    private func takePreparedNextPlayer(for trackID: String) -> AVPlayer? {
        guard preparedNextTrackID == trackID, preparedNextReady else {
            discardPreparedNextTrack()
            return nil
        }
        let player = preparedNextPlayer
        preparedNextStatusObservation = nil
        preparedNextPlayer = nil
        preparedNextTrackID = nil
        preparedNextReady = false
        return player
    }

    private func discardPreparedNextTrack() {
        preparedNextStatusObservation = nil
        preparedNextPlayer?.cancelPendingPrerolls()
        preparedNextPlayer?.pause()
        preparedNextPlayer?.replaceCurrentItem(with: nil)
        preparedNextPlayer = nil
        preparedNextTrackID = nil
        preparedNextReady = false
    }

    private func handleTrackEnded(_ endedPlayer: AVPlayer, trackID: String) {
        guard player === endedPlayer,
              self.trackID == trackID,
              isPlaying,
              handledEndTrackID != trackID,
              crossfadePlayer == nil,
              crossfadeTask == nil else { return }
        handledEndTrackID = trackID

        if repeatMode == .one {
            isRepeatSeekInProgress = true
            endedPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak endedPlayer] finished in
                Task { @MainActor [weak self, weak endedPlayer] in
                    guard let self, let endedPlayer else { return }
                    self.isRepeatSeekInProgress = false
                    guard finished, self.player === endedPlayer, self.trackID == trackID else { return }
                    self.handledEndTrackID = nil
                    endedPlayer.play()
                    self.isPlaying = true
                    self.timestamp = .now
                }
            }
        } else if hasNextTrack {
            isPlaying = false
            Task {
                do { try await nextTrack() }
                catch { playbackError = "Could not start the next track: \(error.localizedDescription)" }
            }
        } else {
            playbackIntent = false
            isPlaying = false
            timestamp = .now
        }
    }

    private func cancelCrossfade() {
        crossfadeTask?.cancel()
        crossfadeTask = nil
        crossfadePlayer?.pause()
        crossfadePlayer?.replaceCurrentItem(with: nil)
        crossfadePlayer = nil
        player?.volume = Float(volume)
    }

    private func beginCrossfade(to nextIndex: Int, outgoingTrackID: String, duration fadeDuration: TimeInterval) {
        guard crossfadePlayer == nil,
              queue.indices.contains(nextIndex),
              let outgoingPlayer = player,
              trackID == outgoingTrackID else { return }

        let nextTrack = queue[nextIndex]
        let incoming = takePreparedNextPlayer(for: nextTrack.id) ?? makePlayer(for: nextTrack)
        incoming.volume = 0
        crossfadePlayer = incoming
        incoming.play()

        let steps = max(1, Int(fadeDuration / 0.05))
        crossfadeTask = Task { @MainActor [weak self] in
            for step in 0...steps {
                guard let self,
                      !Task.isCancelled,
                      self.crossfadePlayer === incoming,
                      self.trackID == outgoingTrackID else { return }
                let progress = Double(step) / Double(steps)
                let envelope = self.transitionCurve.levels(at: progress)
                outgoingPlayer.volume = envelope.outgoing * Float(self.volume)
                incoming.volume = envelope.incoming * Float(self.volume)
                if step < steps {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            guard let self, self.crossfadePlayer === incoming else { return }
            self.finishCrossfade(to: incoming, queueIndex: nextIndex)
        }
    }

    private func scheduleCrossfade(to nextIndex: Int, outgoingTrackID: String, duration: TimeInterval, delay: TimeInterval) {
        guard crossfadeTask == nil else { return }
        crossfadeTask = Task { @MainActor [weak self] in
            if delay > 0 {
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
            }
            guard let self,
                  !Task.isCancelled,
                  self.trackID == outgoingTrackID,
                  self.crossfadePlayer == nil else { return }
            self.crossfadeTask = nil
            self.beginCrossfade(to: nextIndex, outgoingTrackID: outgoingTrackID, duration: duration)
        }
    }

    private func finishCrossfade(to incoming: AVPlayer, queueIndex: Int) {
        guard queue.indices.contains(queueIndex) else {
            cancelCrossfade()
            return
        }
        let track = queue[queueIndex]
        removeProgressObserver()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        incoming.volume = Float(volume)
        player = incoming
        crossfadePlayer = nil
        crossfadeTask = nil
        currentQueueIndex = queueIndex
        trackID = track.id
        title = track.title
        artist = track.artist
        album = track.album
        duration = track.duration
        let incomingTime = incoming.currentTime().seconds
        elapsedTime = incomingTime.isFinite ? incomingTime : 0
        isPlaying = true
        timestamp = .now
        installProgressObserver(on: incoming, trackID: track.id)
        prepareNextTrack(after: queueIndex)
        onTrackChanged?(track)
    }

    func seek(to seconds: TimeInterval) {
        guard let activePlayer = player else { return }
        cancelCrossfade()
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        seekGeneration &+= 1
        let request = seekGeneration
        let shouldResume = playbackIntent
        isSeeking = true
        elapsedTime = target
        timestamp = .now
        let destination = CMTime(seconds: target, preferredTimescale: 600)
        let seekTolerance = CMTime(seconds: 0.12, preferredTimescale: 600)
        activePlayer.seek(to: destination, toleranceBefore: seekTolerance, toleranceAfter: seekTolerance) { [weak self, weak activePlayer] _ in
            Task { @MainActor [weak self, weak activePlayer] in
                guard let self, let activePlayer,
                      self.seekGeneration == request,
                      self.player === activePlayer else { return }
                self.isSeeking = false
                let landedTime = activePlayer.currentTime().seconds
                if landedTime.isFinite { self.elapsedTime = landedTime }
                self.timestamp = .now
                if shouldResume, activePlayer.rate == 0 {
                    activePlayer.play()
                    self.isPlaying = true
                }
            }
        }
    }

    private func installProgressObserver(on player: AVPlayer, trackID observedTrackID: String) {
        removeProgressObserver()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 10),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.trackID == observedTrackID, time.seconds.isFinite else { return }
                if !self.isSeeking {
                    self.elapsedTime = time.seconds
                    self.timestamp = .now
                }
                if let itemDuration = player.currentItem?.duration.seconds,
                   itemDuration.isFinite,
                   itemDuration > 0 {
                    self.duration = itemDuration
                    let currentIndex = self.currentQueueIndex ?? -1
                    let nextIndex = self.queueIndex(after: currentIndex)
                    let remaining = itemDuration - time.seconds
                    if !self.isSeeking,
                       self.repeatMode != .one,
                       self.crossfadeEnabled,
                       self.crossfadePlayer == nil,
                       self.crossfadeTask == nil,
                       let nextIndex,
                       nextIndex != currentIndex,
                       self.queue.indices.contains(currentIndex) {
                        let currentBPM = self.queue[currentIndex].bpm
                        let nextBPM = self.queue[nextIndex].bpm
                        let bpmPair = currentBPM.flatMap { outgoing in
                            nextBPM.map { incoming in (outgoing, incoming) }
                        }
                        let matchedBeatTempo: Double? = bpmPair.flatMap { outgoing, incoming in
                            guard outgoing > 0, incoming > 0 else { return nil }
                            let ratio = max(outgoing, incoming) / min(outgoing, incoming)
                            if ratio <= 1.06 { return (outgoing + incoming) / 2 }
                            if abs(ratio - 2) <= 0.12 { return max(outgoing, incoming) }
                            return nil
                        }
                        if self.beatSyncEnabled, let matchedBeatTempo {
                            let beatDuration = 60 / matchedBeatTempo
                            let phase = time.seconds.truncatingRemainder(dividingBy: beatDuration)
                            let delayToBeat = phase < beatDuration * 0.08 ? 0 : beatDuration - phase
                            if remaining <= self.crossfadeDuration + delayToBeat {
                                let delay = min(delayToBeat, max(0, remaining - 0.12))
                                let available = min(self.crossfadeDuration, max(0.1, remaining - delay))
                                let beatCount = max(1, (available / beatDuration).rounded())
                                let beatAlignedDuration = min(available, beatCount * beatDuration)
                                self.scheduleCrossfade(to: nextIndex, outgoingTrackID: observedTrackID, duration: beatAlignedDuration, delay: delay)
                            }
                        } else if remaining <= self.crossfadeDuration {
                            self.scheduleCrossfade(to: nextIndex, outgoingTrackID: observedTrackID, duration: min(self.crossfadeDuration, max(0.1, remaining)), delay: 0)
                        }
                    }
                    if !self.isSeeking, time.seconds >= itemDuration - 0.15, self.isPlaying, self.crossfadePlayer == nil, self.crossfadeTask == nil {
                        self.handleTrackEnded(player, trackID: observedTrackID)
                    }
                }
            }
        }
        timeObserverPlayer = player
    }
}

struct BreeQueuedTrack: Identifiable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval
    let bpm: Double?
    let artworkID: String
    let artworkURL: URL?
    let url: URL
}

enum BreeTransitionCurve: String, CaseIterable, Identifiable {
    case fade
    case rise

    var id: String { rawValue }
    var title: String { self == .fade ? "Equal power fade" : "Rise" }

    func levels(at progress: Double) -> (outgoing: Float, incoming: Float) {
        let p = min(1, max(0, progress))
        switch self {
        case .fade:
            return (Float(cos(p * .pi / 2)), Float(sin(p * .pi / 2)))
        case .rise:
            let eased = p * p * (3 - 2 * p)
            return (Float(1 - eased), Float(eased))
        }
    }
}

enum BreeRepeatMode: String, CaseIterable, Identifiable {
    case off
    case one
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Repeat Off"
        case .one: "Repeat One"
        case .all: "Repeat All"
        }
    }

    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

private enum BreePlaybackError: LocalizedError {
    case audioSessionActivationFailed(String)

    var errorDescription: String? {
        switch self {
        case .audioSessionActivationFailed(let details):
            return "iOS could not activate audio playback: \(details)"
        }
    }
}
#endif
