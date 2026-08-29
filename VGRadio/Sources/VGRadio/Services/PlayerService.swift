import AppKit
import AVFoundation
import MediaPlayer
import Observation

enum RepeatMode { case off, all, one }

/// Each queue entry carries its own album/covers so a track queued from a
/// different album (via "Play Next") shows its own cover and album title
/// instead of whatever album the queue happened to start from.
struct QueueItem {
    let track: Track
    let album: AlbumSummary
    let covers: [Cover]
}

@MainActor
@Observable
final class PlayerService {
    private(set) var currentItem: QueueItem?
    var currentTrack: Track? { currentItem?.track }
    var currentAlbum: AlbumSummary? { currentItem?.album }
    var currentCovers: [Cover] { currentItem?.covers ?? [] }
    var currentCoverIndex: Int = 0
    var hiddenTracks: HiddenTracksStore?
    var offline: OfflineStore?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var volume: Double = 0.8 {
        didSet { player?.volume = Float(volume); if volume > 0 { isMuted = false }; stateDidChange() }
    }
    var isMuted: Bool = false {
        didSet { player?.isMuted = isMuted; stateDidChange() }
    }
    var isShuffle = false {
        didSet { stateDidChange() }
    }
    var repeatMode: RepeatMode = .off {
        didSet { stateDidChange() }
    }
    /// Panel visibility is local UI, not playback state — deliberately not observed.
    var showQueue = false

    /// Called after every discrete state change (track, play/pause, seek, volume,
    /// queue). High-frequency position ticks are excluded: an observer that needs
    /// the live position interpolates it from `currentTime` plus wall time.
    /// Observers that publish over the network must throttle — `volume` fires on
    /// every step of a slider drag.
    var onStateChange: ((PlayerService) -> Void)?

    private func stateDidChange() { onStateChange?(self) }

    /// Returns true when the action was handled by another device and must not
    /// run locally. Installed by ConnectService; nil means everything is local.
    var remoteSink: ((String, ConnectPayload?) -> Bool)?

    /// True while another device owns playback. Silences this app's Now Playing
    /// entry: leaving it registered makes macOS treat us as a playing app and
    /// the media keys get fought over between the two instances.
    var isRemote = false {
        didSet {
            guard isRemote != oldValue else { return }
            if isRemote {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                MPNowPlayingInfoCenter.default().playbackState = .stopped
            } else {
                updateNowPlayingInfo()
            }
        }
    }

    private func remote(_ type: String, _ payload: ConnectPayload? = nil) -> Bool {
        remoteSink?(type, payload) ?? false
    }

    /// Stops audio without touching shared state, for when playback moves to
    /// another device.
    func pauseForHandoff() {
        player?.pause()
        isPlaying = false
    }

    private var player: AVPlayer?
    private(set) var queue: [QueueItem] = []
    private(set) var queueIndex: Int = 0
    private var timeObserver: Any?
    private var artwork: MPMediaItemArtwork?
    private var artworkTrackID: String?

    init() { setupRemoteCommands() }

    // MARK: - Playback control

    func play(track: Track, in album: AlbumSummary, queue tracks: [Track], covers: [Cover] = []) {
        // The remote device rebuilds the queue from its own source, so only the
        // context travels — not every track in the album.
        if remote("playContext", ConnectPayload(albumId: album.id, startTrackId: track.id)) { return }
        self.queue = tracks.map { QueueItem(track: $0, album: album, covers: covers) }
        self.queueIndex = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
        guard queue.indices.contains(queueIndex) else { return }
        load(item: queue[queueIndex])
    }

    /// Takes over a queue from another device: same tracks, same position.
    /// Deliberately unguarded — by the time this runs, this app is already the
    /// active device.
    func adopt(items: [QueueItem], index: Int, positionSec: Double, play: Bool) {
        guard !items.isEmpty else { return }
        queue = items
        queueIndex = min(max(0, index), items.count - 1)
        load(item: queue[queueIndex])
        if positionSec > 0 { seek(to: positionSec) }
        if !play {
            player?.pause()
            isPlaying = false
            updateNowPlayingInfo()
        }
    }

    func togglePlay() {
        if remote("toggle") { return }
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying = !isPlaying
        updateNowPlayingInfo()
        stateDidChange()
    }

    private func isSkippable(_ item: QueueItem) -> Bool {
        hiddenTracks?.isHidden(item.track.id) == true
    }

    func next() {
        if remote("next") { return }
        if repeatMode == .one {
            seek(to: 0); player?.play(); isPlaying = true; return
        }
        if isShuffle {
            let candidates = queue.indices.filter { $0 != queueIndex && !isSkippable(queue[$0]) }
            guard let idx = candidates.randomElement() else { return }
            queueIndex = idx; load(item: queue[idx]); return
        }
        var idx = queueIndex + 1
        while idx < queue.count && isSkippable(queue[idx]) { idx += 1 }
        if idx >= queue.count {
            guard repeatMode == .all else { return }
            idx = 0
            while idx < queue.count && isSkippable(queue[idx]) { idx += 1 }
            guard idx < queue.count else { return }
        }
        queueIndex = idx
        load(item: queue[idx])
    }

    func removeFromQueue(at index: Int) {
        if remote("queueRemove", ConnectPayload(index: index)) { return }
        guard index < queue.count else { return }
        queue.remove(at: index)
        if index < queueIndex { queueIndex -= 1 }
        else if index == queueIndex { queueIndex = min(queueIndex, queue.count - 1) }
        stateDidChange()
    }

    func playAt(index: Int) {
        guard queue.indices.contains(index) else { return }
        if remote("playContext", ConnectPayload(albumId: queue[index].album.id, startTrackId: queue[index].track.id)) { return }
        queueIndex = index
        load(item: queue[index])
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        if let f = source.first, remote("queueMove", ConnectPayload(from: f, to: destination)) { return }
        queue.move(fromOffsets: source, toOffset: destination)
        queueIndex = queue.firstIndex(where: { $0.track.id == currentTrack?.id }) ?? queueIndex
        stateDidChange()
    }

    func previous() {
        if remote("prev") { return }
        if currentTime > 3 { seek(to: 0); return }
        var idx = queueIndex - 1
        while idx >= 0 && isSkippable(queue[idx]) { idx -= 1 }
        guard idx >= 0 else { return }
        queueIndex = idx
        load(item: queue[idx])
    }

    /// Inserts right after the current position. `album`/`covers` default to those
    /// of whatever is playing, for callers queueing from the same album.
    func playNext(_ track: Track, album: AlbumSummary? = nil, covers: [Cover] = []) {
        guard let itemAlbum = album ?? currentItem?.album else { return }
        if remote("queueAdd", ConnectPayload(albumId: itemAlbum.id, trackId: track.id)) { return }
        let item = QueueItem(track: track, album: itemAlbum,
                             covers: album == nil ? (currentItem?.covers ?? []) : covers)
        queue.insert(item, at: min(queueIndex + 1, queue.count))
        stateDidChange()
    }

    // Volume, mute, shuffle and repeat are plain stored properties so views can
    // read them, but mutating them has to go through these so the action can be
    // routed to another device instead.
    func setVolume(_ v: Double) {
        if remote("volume", ConnectPayload(volume: v)) { return }
        volume = v
    }

    func toggleMute() {
        if remote("mute") { return }
        isMuted.toggle()
    }

    func toggleShuffle() {
        if remote("shuffle") { return }
        isShuffle.toggle()
    }

    func cycleRepeat() {
        if remote("repeat") { return }
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    func seek(to seconds: Double) {
        if remote("seek", ConnectPayload(positionSec: seconds)) { return }
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
        updateNowPlayingInfo()
        stateDidChange()
    }

    // MARK: - Private

    private func load(item: QueueItem) {
        let track = item.track
        // Local file preferred (faster, works offline); otherwise stream — even
        // in offline mode. Offline mode no longer hard-blocks non-downloaded
        // tracks; if there's really no network, AVPlayer just fails to load.
        guard let url = offline?.localURL(for: track.id) ?? APIClient.shared.streamURL(for: track) else { return }
        removeTimeObserver()
        let playerItem = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
            player?.volume = Float(volume)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        // Reset the cover picker only when moving to a different album, so paging
        // through one album's covers survives a track change.
        if currentItem?.album.id != item.album.id { currentCoverIndex = 0 }
        currentItem = item
        duration = Double(track.durationSec)
        currentTime = 0
        player?.play()
        isPlaying = true
        observeTime()
        observeEnd()
        updateNowPlayingInfo()
        if let albumId = currentAlbum?.id {
            Task { await APIClient.shared.recordHistory(trackId: track.id, albumId: albumId) }
        }
        stateDidChange()
    }

    private func observeTime() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            Task { @MainActor [weak self] in
                self?.currentTime = t.seconds
                self?.updateNowPlayingElapsed()
            }
        }
    }

    private func observeEnd() {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.next() }
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
    }

    // MARK: - Media keys

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        // Commands we don't implement must be explicitly disabled: leaving them
        // enabled makes the system think we handle them and then get no response,
        // which costs us priority as the Now Playing app.
        for cmd in [cc.skipForwardCommand, cc.skipBackwardCommand,
                    cc.seekForwardCommand, cc.seekBackwardCommand,
                    cc.changeRepeatModeCommand, cc.changeShuffleModeCommand,
                    cc.ratingCommand, cc.likeCommand, cc.dislikeCommand,
                    cc.bookmarkCommand, cc.enableLanguageOptionCommand] as [MPRemoteCommand] {
            cmd.isEnabled = false
        }
        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in if !self.isPlaying { self.togglePlay() } }
            return .success
        }
        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in if self.isPlaying { self.togglePlay() } }
            return .success
        }
        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.togglePlay() }
            return .success
        }
        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.next() }
            return .success
        }
        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.previous() }
            return .success
        }
        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = currentTrack else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        if let album = currentAlbum {
            info[MPMediaItemPropertyAlbumTitle] = album.title
            info[MPMediaItemPropertyArtist] = album.platform
        }
        if let art = artwork { info[MPMediaItemPropertyArtwork] = art }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
        loadArtworkIfNeeded()
    }

    /// Fetch the current cover once per track and re-publish it into the Now Playing
    /// entry — without artwork macOS shows us as a blank tile next to fully-populated
    /// apps like Spotify.
    private func loadArtworkIfNeeded() {
        guard let track = currentTrack else { return }
        guard artworkTrackID != track.id else { return }
        artworkTrackID = track.id
        artwork = nil
        let idx = min(currentCoverIndex, max(0, currentCovers.count - 1))
        guard !currentCovers.isEmpty,
              let url = AlbumCoverView.resolveURL(currentCovers[idx].url) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            await MainActor.run {
                guard let self, self.currentTrack?.id == track.id else { return }
                self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = self.artwork
            }
        }
    }

    private func updateNowPlayingElapsed() {
        guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    }
}
