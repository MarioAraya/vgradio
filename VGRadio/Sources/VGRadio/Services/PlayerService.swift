import AVFoundation
import Observation

@Observable
final class PlayerService {
    private(set) var currentTrack: Track?
    private(set) var currentAlbum: AlbumSummary?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    private var player: AVPlayer?
    private var queue: [Track] = []
    private var queueIndex = 0
    private var timeObserver: Any?

    // MARK: - Playback control

    func play(track: Track, in album: AlbumSummary, queue tracks: [Track]) {
        self.queue = tracks
        self.queueIndex = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
        self.currentAlbum = album
        load(track: track)
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying = !isPlaying
    }

    func next() {
        guard queueIndex + 1 < queue.count else { return }
        queueIndex += 1
        load(track: queue[queueIndex])
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0); return
        }
        guard queueIndex > 0 else { return }
        queueIndex -= 1
        load(track: queue[queueIndex])
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
    }

    // MARK: - Private

    private func load(track: Track) {
        guard let url = APIClient.shared.streamURL(for: track) else { return }
        removeTimeObserver()
        let item = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: item)
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
    }

    private func observeTime() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            self?.currentTime = t.seconds
        }
    }

    private func observeEnd() {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { [weak self] _ in
            self?.next()
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
    }
}
