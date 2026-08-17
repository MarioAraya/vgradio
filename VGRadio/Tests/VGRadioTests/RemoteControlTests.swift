import MediaPlayer
import XCTest
@testable import VGRadio

@MainActor
final class RemoteControlTests: XCTestCase {

    private func seeded() -> PlayerService {
        let p = PlayerService()
        let tracks = [
            Track(id: "trk_1", index: 1, name: "One", durationSec: 100, sizeBytes: 0,
                  streamUrl: "/tracks/trk_1/stream", downloadUrl: "/tracks/trk_1/download"),
            Track(id: "trk_2", index: 2, name: "Two", durationSec: 100, sizeBytes: 0,
                  streamUrl: "/tracks/trk_2/stream", downloadUrl: "/tracks/trk_2/download"),
        ]
        let album = AlbumSummary(id: "alb_1", title: "Metroid Prime", platform: "GC",
                                 year: 2002, albumType: "Gamerip", trackCount: 2,
                                 totalDurationSec: 200, coverUrls: [])
        p.play(track: tracks[0], in: album, queue: tracks)
        return p
    }

    /// Every control must consult the sink. A single missed guard means one
    /// button plays here instead of on the device the user is controlling.
    func testEveryControlRoutesThroughTheSink() {
        let p = seeded()
        let queueBefore = p.queue.count
        let indexBefore = p.queueIndex
        let shuffleBefore = p.isShuffle
        let repeatBefore = p.repeatMode

        var sent: [String] = []
        p.remoteSink = { type, _ in sent.append(type); return true }

        let album = AlbumSummary(id: "alb_2", title: "Super Metroid", platform: "SNES",
                                 year: 1994, albumType: "Gamerip", trackCount: 1,
                                 totalDurationSec: 100, coverUrls: [])
        let extra = Track(id: "trk_9", index: 9, name: "Nine", durationSec: 100, sizeBytes: 0,
                          streamUrl: "/tracks/trk_9/stream", downloadUrl: "/tracks/trk_9/download")

        p.play(track: extra, in: album, queue: [extra])
        p.togglePlay()
        p.seek(to: 10)
        p.setVolume(0.3)
        p.toggleMute()
        p.toggleShuffle()
        p.cycleRepeat()
        p.next()
        p.previous()
        p.playNext(extra, album: album)
        p.removeFromQueue(at: 0)
        p.moveInQueue(from: IndexSet(integer: 0), to: 1)

        XCTAssertEqual(sent, [
            "playContext", "toggle", "seek", "volume", "mute", "shuffle", "repeat",
            "next", "prev", "queueAdd", "queueRemove", "queueMove",
        ])

        // Nothing was applied locally.
        XCTAssertEqual(p.queue.count, queueBefore)
        XCTAssertEqual(p.queueIndex, indexBefore)
        XCTAssertEqual(p.isShuffle, shuffleBefore)
        XCTAssertEqual(p.repeatMode, repeatBefore)
        XCTAssertEqual(p.currentTrack?.id, "trk_1")
    }

    func testControlsActLocallyOnceTheSinkDeclines() {
        let p = seeded()
        p.remoteSink = { _, _ in false }
        p.toggleShuffle()
        XCTAssertTrue(p.isShuffle)
        p.cycleRepeat()
        XCTAssertEqual(p.repeatMode, .all)
    }

    /// Leaving the Now Playing entry registered while another device plays makes
    /// macOS treat this app as playing, and the media keys get fought over.
    func testRemoteModeClearsNowPlaying() {
        let p = seeded()
        p.isRemote = true
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .stopped)
    }

    func testPauseForHandoffStopsWithoutClearingTheQueue() {
        let p = seeded()
        p.pauseForHandoff()
        XCTAssertFalse(p.isPlaying)
        XCTAssertEqual(p.queue.count, 2)
        XCTAssertEqual(p.currentTrack?.id, "trk_1")
    }

    func testDeviceIdentityIsStableAcrossInstances() {
        let a = ConnectService()
        let b = ConnectService()
        XCTAssertEqual(a.deviceID, b.deviceID, "device id must persist in UserDefaults")
        XCTAssertFalse(a.isRemote, "no active device means nothing is remote")
    }

    /// "Reproducir acá" must continue the music, not just move the active role.
    func testAdoptContinuesTheQueueAtThePreviousPosition() {
        let p = PlayerService()
        let album = AlbumSummary(id: "alb_1", title: "Metroid Prime", platform: "GC",
                                 year: 2002, albumType: "Gamerip", trackCount: 2,
                                 totalDurationSec: 200, coverUrls: [])
        let items = [
            QueueItem(track: Track(id: "trk_1", index: 1, name: "One", durationSec: 100,
                                   sizeBytes: 0, streamUrl: "/tracks/trk_1/stream",
                                   downloadUrl: "/tracks/trk_1/download"),
                      album: album, covers: []),
            QueueItem(track: Track(id: "trk_2", index: 2, name: "Two", durationSec: 100,
                                   sizeBytes: 0, streamUrl: "/tracks/trk_2/stream",
                                   downloadUrl: "/tracks/trk_2/download"),
                      album: album, covers: []),
        ]

        p.adopt(items: items, index: 1, positionSec: 42, play: false)

        XCTAssertEqual(p.queue.count, 2)
        XCTAssertEqual(p.queueIndex, 1)
        XCTAssertEqual(p.currentTrack?.id, "trk_2")
        XCTAssertEqual(p.currentTime, 42, accuracy: 0.01)
        XCTAssertFalse(p.isPlaying, "play:false must hand over paused")
    }

    func testAdoptClampsAnOutOfRangeIndex() {
        let p = PlayerService()
        let album = AlbumSummary(id: "alb_1", title: "A", platform: "", year: 0,
                                 albumType: "", trackCount: 1, totalDurationSec: 0, coverUrls: [])
        let items = [QueueItem(track: Track(id: "t", index: 1, name: "T", durationSec: 10,
                                            sizeBytes: 0, streamUrl: "/tracks/t/stream",
                                            downloadUrl: "/tracks/t/download"),
                               album: album, covers: [])]
        p.adopt(items: items, index: 99, positionSec: 0, play: false)
        XCTAssertEqual(p.queueIndex, 0)
    }

    func testRepeatModeWireValues() {
        XCTAssertEqual(RepeatMode.off.wireValue, "off")
        XCTAssertEqual(RepeatMode.all.wireValue, "all")
        XCTAssertEqual(RepeatMode.one.wireValue, "one")
    }
}
