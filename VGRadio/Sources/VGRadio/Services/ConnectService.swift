import AppKit
import Foundation
import Observation

/// VGRadio Connect client: keeps this Mac registered as a device, streams the
/// hub's events, and either publishes playback state (when this device is the
/// active one) or turns the local player into a remote control.
///
/// If the stream is down the app behaves exactly as it did before Connect
/// existed — remote control must never be able to break local playback.
@MainActor
@Observable
final class ConnectService {
    private(set) var devices: [ConnectDevice] = []
    private(set) var activeDeviceID: String = ""
    private(set) var remoteState: ConnectState?
    private(set) var isConnected = false

    // What the player bar shows while another device plays. The queue carries
    // only IDs, so the current album is fetched once and cached.
    private(set) var remoteTrack: Track?
    private(set) var remoteAlbum: AlbumSummary?
    private(set) var remoteCovers: [Cover] = []

    /// Interpolated between state events so the progress bar moves smoothly
    /// without a network update per second.
    private(set) var remotePosition: Double = 0

    private var albumCache: [String: Album] = [:]
    private var tickTask: Task<Void, Never>?

    /// True when another device owns playback: this app renders and commands,
    /// but plays no audio.
    var isRemote: Bool { !activeDeviceID.isEmpty && activeDeviceID != deviceID }

    var activeDevice: ConnectDevice? { devices.first(where: { $0.id == activeDeviceID }) }

    /// Devices other than this one. The picker hides itself when empty: a lone
    /// device has nothing to connect to.
    var otherDevices: [ConnectDevice] { devices.filter { $0.id != deviceID } }

    let deviceID: String
    var deviceName: String {
        didSet {
            UserDefaults.standard.set(deviceName, forKey: Self.nameKey)
            Task { try? await APIClient.shared.registerDevice(id: deviceID, name: deviceName) }
        }
    }

    private static let idKey = "vgradio.deviceId"
    private static let nameKey = "vgradio.deviceName"

    private weak var player: PlayerService?
    private var streamTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var running = false

    /// The shared APIClient session has a 30s request timeout, which would tear
    /// down an idle stream. This one tolerates long gaps between events while
    /// still reusing the cookie jar that carries the session.
    private let streamSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = .infinity
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        return URLSession(configuration: cfg)
    }()

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.idKey) {
            deviceID = saved
        } else {
            let generated = "mac_" + UUID().uuidString.prefix(8).lowercased()
            UserDefaults.standard.set(generated, forKey: Self.idKey)
            deviceID = generated
        }
        deviceName = UserDefaults.standard.string(forKey: Self.nameKey)
            ?? Host.current().localizedName
            ?? "Mac"
    }

    // MARK: - Lifecycle

    func start(player: PlayerService) {
        guard !running else { return }
        running = true
        self.player = player

        player.onStateChange = { [weak self] p in self?.schedulePublish(from: p) }
        player.remoteSink = { [weak self] type, payload in
            guard let self, self.isRemote else { return false }
            Task { await APIClient.shared.sendCommand(deviceID: self.deviceID, type: type, payload: payload) }
            return true
        }

        streamTask = Task { await self.streamLoop() }
        heartbeatTask = Task { await self.heartbeatLoop() }
    }

    func stop() {
        running = false
        streamTask?.cancel(); streamTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        publishTask?.cancel(); publishTask = nil
        tickTask?.cancel(); tickTask = nil
        player?.onStateChange = nil
        player?.remoteSink = nil
        player?.isRemote = false
        isConnected = false
        devices = []
        activeDeviceID = ""
        remoteState = nil
        let id = deviceID
        Task { await APIClient.shared.unregisterDevice(id: id) }
    }

    /// Moves playback to a device, or takes it over locally.
    func transfer(to id: String, play: Bool = true) {
        Task {
            try? await APIClient.shared.transferPlayback(to: id, play: play)
        }
    }

    // MARK: - Stream

    private func streamLoop() async {
        var attempt = 0
        while running && !Task.isCancelled {
            do {
                try await readStream()
                attempt = 0
            } catch {
                isConnected = false
            }
            guard running && !Task.isCancelled else { return }
            // Capped exponential backoff: a backend restart must not turn every
            // running app into a reconnect storm.
            let delay = min(30.0, pow(2.0, Double(attempt)))
            attempt += 1
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func readStream() async throws {
        let req = try APIClient.shared.connectEventsRequest(deviceID: deviceID, name: deviceName)
        let (bytes, response) = try await streamSession.bytes(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VGError.jobFailed("connect stream refused")
        }
        isConnected = true

        var event = ""
        var payload = ""
        for try await line in bytes.lines {
            if Task.isCancelled || !running { return }
            if line.hasPrefix("event: ") {
                event = String(line.dropFirst("event: ".count))
            } else if line.hasPrefix("data: ") {
                payload = String(line.dropFirst("data: ".count))
            } else if line.isEmpty {
                if !event.isEmpty { handle(event: event, json: payload) }
                event = ""; payload = ""
            }
            // ": ping" and any other comment line is ignored on purpose.
        }
        isConnected = false
    }

    private func handle(event: String, json: String) {
        guard let data = json.data(using: .utf8) else { return }
        let dec = JSONDecoder()
        switch event {
        case "hello":
            guard let hello = try? dec.decode(ConnectHello.self, from: data) else { return }
            devices = hello.devices
            activeDeviceID = hello.activeDeviceId
            remoteState = hello.state
            syncRemoteFlag()
        case "devices":
            guard let list = try? dec.decode([ConnectDevice].self, from: data) else { return }
            devices = list
            activeDeviceID = list.first(where: { $0.isActive })?.id ?? ""
            syncRemoteFlag()
        case "state":
            remoteState = try? dec.decode(ConnectState.self, from: data)
            hydrateCurrent()
        case "transfer":
            guard let t = try? dec.decode(ConnectTransfer.self, from: data) else { return }
            activeDeviceID = t.activeDeviceId
            remoteState = t.state
            syncRemoteFlag()
        case "command":
            guard let cmd = try? dec.decode(ConnectCommand.self, from: data) else { return }
            run(cmd)
        default:
            break
        }
    }

    /// Keeps the player's own flag in step, so it can silence Now Playing and
    /// route controls without reaching back into this service.
    private func syncRemoteFlag() {
        guard let player else { return }
        let remote = isRemote
        if remote && player.isPlaying { player.pauseForHandoff() }
        player.isRemote = remote
        hydrateCurrent()
    }

    /// Resolves the currently playing entry into a track/album the bar can draw,
    /// and restarts position interpolation.
    private func hydrateCurrent() {
        tickTask?.cancel(); tickTask = nil

        guard isRemote, let state = remoteState,
              let entry = state.queue?.indices.contains(state.queueIndex) == true
                ? state.queue?[state.queueIndex] : nil else {
            remoteTrack = nil; remoteAlbum = nil; remoteCovers = []; remotePosition = 0
            return
        }

        remotePosition = state.positionSec
        if state.isPlaying {
            let base = state.positionSec
            let start = Date()
            tickTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self else { return }
                    self.remotePosition = base + Date().timeIntervalSince(start)
                }
            }
        }

        if let album = albumCache[entry.albumId] {
            apply(album, trackID: entry.trackId)
            return
        }
        Task { [weak self] in
            guard let album = try? await APIClient.shared.album(entry.albumId) else { return }
            guard let self else { return }
            self.albumCache[entry.albumId] = album
            self.apply(album, trackID: entry.trackId)
        }
    }

    private func apply(_ album: Album, trackID: String) {
        remoteAlbum = album.summary
        remoteCovers = album.covers
        remoteTrack = album.tracks.first(where: { $0.id == trackID })
    }

    // MARK: - Incoming commands

    private func run(_ cmd: ConnectCommand) {
        guard let player else { return }
        // Executing a command must not send it straight back out.
        let sink = player.remoteSink
        player.remoteSink = nil
        defer { player.remoteSink = sink }

        let p = cmd.payload
        switch cmd.type {
        case "toggle": player.togglePlay()
        case "play":   if !player.isPlaying { player.togglePlay() }
        case "pause":  if player.isPlaying { player.togglePlay() }
        case "next":   player.next()
        case "prev":   player.previous()
        case "seek":   player.seek(to: p?.positionSec ?? 0)
        case "volume": player.setVolume(p?.volume ?? player.volume)
        case "mute":   player.toggleMute()
        case "shuffle": player.toggleShuffle()
        case "repeat":  player.cycleRepeat()
        case "playContext": playContext(p)
        case "queueAdd":    queueAdd(p)
        case "queueRemove": if let i = p?.index { player.removeFromQueue(at: i) }
        case "queueMove":
            if let f = p?.from, let t = p?.to {
                player.moveInQueue(from: IndexSet(integer: f), to: t)
            }
        default: break
        }
    }

    private func playContext(_ p: ConnectPayload?) {
        guard let albumID = p?.albumId, let player else { return }
        Task {
            guard let album = try? await APIClient.shared.album(albumID) else { return }
            let summary = album.summary
            let start = album.tracks.first(where: { $0.id == p?.startTrackId }) ?? album.tracks.first
            guard let start else { return }
            player.play(track: start, in: summary, queue: album.tracks, covers: album.covers)
        }
    }

    private func queueAdd(_ p: ConnectPayload?) {
        guard let albumID = p?.albumId, let trackID = p?.trackId, let player else { return }
        Task {
            guard let album = try? await APIClient.shared.album(albumID),
                  let track = album.tracks.first(where: { $0.id == trackID }) else { return }
            player.playNext(track, album: album.summary, covers: album.covers)
        }
    }

    // MARK: - Publishing

    private func schedulePublish(from player: PlayerService) {
        guard activeDeviceID == deviceID else { return }
        // A track change fires several discrete updates in a row; coalesce them.
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            await APIClient.shared.publishState(deviceID: self.deviceID, state: self.snapshot(of: player))
        }
    }

    private func snapshot(of player: PlayerService) -> ConnectState {
        ConnectState(
            isPlaying: player.isPlaying,
            positionSec: player.currentTime,
            volume: player.volume,
            isMuted: player.isMuted,
            isShuffle: player.isShuffle,
            repeatMode: player.repeatMode.wireValue,
            queueIndex: player.queueIndex,
            coverIndex: player.currentCoverIndex,
            queue: player.queue.map { ConnectQueueEntry(trackId: $0.track.id, albumId: $0.album.id) }
        )
    }

    /// Re-registers on a timer and, while this device is playing, republishes
    /// position so spectators can resync their interpolation.
    private func heartbeatLoop() async {
        while running && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard running, !Task.isCancelled else { return }
            if let player, activeDeviceID == deviceID, player.isPlaying {
                await APIClient.shared.publishState(deviceID: deviceID, state: snapshot(of: player))
            } else {
                _ = try? await APIClient.shared.registerDevice(id: deviceID, name: deviceName)
            }
        }
    }
}

extension RepeatMode {
    var wireValue: String {
        switch self {
        case .off: "off"
        case .all: "all"
        case .one: "one"
        }
    }
}

extension Album {
    /// The summary shape the player stores alongside each queue entry.
    var summary: AlbumSummary {
        AlbumSummary(id: id, title: title, platform: platform, year: year,
                     albumType: albumType, trackCount: tracks.count,
                     totalDurationSec: totalDurationSec,
                     coverUrls: covers.map { $0.url })
    }
}
