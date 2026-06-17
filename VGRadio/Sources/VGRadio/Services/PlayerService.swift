import AVFoundation
import MediaPlayer
import Observation

enum RepeatMode { case off, all, one }

@MainActor
@Observable
final class PlayerService {
    private(set) var currentTrack: Track?
    private(set) var currentAlbum: AlbumSummary?
    private(set) var currentCovers: [Cover] = []
    var currentCoverIndex: Int = 0
    var hiddenTracks: HiddenTracksStore?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var volume: Double = 0.8 {
        didSet { player?.volume = Float(volume); if volume > 0 { isMuted = false } }
    }
    var isMuted: Bool = false {
        didSet { player?.isMuted = isMuted }
    }
    var isShuffle = false
    var repeatMode: RepeatMode = .off
    var showQueue = false

    private var player: AVPlayer?
    private(set) var queue: [Track] = []
    private(set) var queueIndex: Int = 0
    private var timeObserver: Any?

    init() { setupRemoteCommands() }

    // MARK: - Playback control

    func play(track: Track, in album: AlbumSummary, queue tracks: [Track], covers: [Cover] = []) {
        self.queue = tracks
        self.queueIndex = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
        self.currentAlbum = album
        self.currentCovers = covers
        self.currentCoverIndex = 0
        load(track: track)
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying = !isPlaying
        updateNowPlayingInfo()
    }

    func next() {
        if repeatMode == .one {
            seek(to: 0); player?.play(); isPlaying = true; return
        }
        if isShuffle {
            let candidates = queue.indices.filter { $0 != queueIndex && hiddenTracks?.isHidden(queue[$0].id) != true }
            guard let idx = candidates.randomElement() else { return }
            queueIndex = idx; load(track: queue[idx]); return
        }
        var idx = queueIndex + 1
        while idx < queue.count && hiddenTracks?.isHidden(queue[idx].id) == true { idx += 1 }
        if idx >= queue.count {
            guard repeatMode == .all else { return }
            idx = 0
            while idx < queue.count && hiddenTracks?.isHidden(queue[idx].id) == true { idx += 1 }
            guard idx < queue.count else { return }
        }
        queueIndex = idx
        load(track: queue[idx])
    }

    func removeFromQueue(at index: Int) {
        guard index < queue.count else { return }
        queue.remove(at: index)
        if index < queueIndex { queueIndex -= 1 }
        else if index == queueIndex { queueIndex = min(queueIndex, queue.count - 1) }
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        queueIndex = queue.firstIndex(where: { $0.id == currentTrack?.id }) ?? queueIndex
    }

    func previous() {
        if currentTime > 3 { seek(to: 0); return }
        var idx = queueIndex - 1
        while idx >= 0 && hiddenTracks?.isHidden(queue[idx].id) == true { idx -= 1 }
        guard idx >= 0 else { return }
        queueIndex = idx
        load(track: queue[idx])
    }

    func playNext(_ track: Track) {
        queue.insert(track, at: min(queueIndex + 1, queue.count))
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
        updateNowPlayingInfo()
    }

    // MARK: - Private

    private func load(track: Track) {
        guard let url = APIClient.shared.streamURL(for: track) else { return }
        removeTimeObserver()
        let item = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: item)
            player?.volume = Float(volume)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        currentTrack = track
        duration = Double(track.durationSec)
        currentTime = 0
        player?.play()
        isPlaying = true
        observeTime()
        observeEnd()
        updateNowPlayingInfo()
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
        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in
            guard let self, !self.isPlaying else { return .commandFailed }
            Task { @MainActor in self.togglePlay() }
            return .success
        }
        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isPlaying else { return .commandFailed }
            Task { @MainActor in self.togglePlay() }
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
        ]
        if let album = currentAlbum {
            info[MPMediaItemPropertyAlbumTitle] = album.title
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    private func updateNowPlayingElapsed() {
        guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    }
}
