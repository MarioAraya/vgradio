import XCTest
@testable import VGRadio

private func makeTrack(_ id: String, _ index: Int) -> Track {
    Track(id: id, index: index, name: "Track \(index)", durationSec: 100, sizeBytes: 0,
          streamUrl: "/tracks/\(id)/stream", downloadUrl: "/tracks/\(id)/download",
          downloaded: false)
}

private func makeAlbum(_ id: String, _ title: String) -> AlbumSummary {
    AlbumSummary(id: id, title: title, platform: "GC", year: 2002, albumType: "Gamerip",
                 trackCount: 2, totalDurationSec: 200, coverUrls: [])
}

@MainActor
final class QueueTests: XCTestCase {

    private func seeded() -> PlayerService {
        let p = PlayerService()
        let tracks = [makeTrack("trk_1", 1), makeTrack("trk_2", 2)]
        p.play(track: tracks[0], in: makeAlbum("alb_1", "Metroid Prime"), queue: tracks)
        return p
    }

    /// The bug this model change fixes: a track queued from another album used to
    /// inherit the playing album's title and covers.
    func testPlayNextKeepsItsOwnAlbum() {
        let p = seeded()
        let other = makeAlbum("alb_2", "Super Metroid")
        let covers = [Cover(url: "/covers/alb_2/0", width: 300, height: 300)]

        p.playNext(makeTrack("trk_9", 9), album: other, covers: covers)

        XCTAssertEqual(p.queue.count, 3)
        XCTAssertEqual(p.queue[1].track.id, "trk_9")
        XCTAssertEqual(p.queue[1].album.title, "Super Metroid")
        XCTAssertEqual(p.queue[1].covers.count, 1)
        // The playing entry is untouched.
        XCTAssertEqual(p.queue[0].album.title, "Metroid Prime")
        XCTAssertEqual(p.currentAlbum?.title, "Metroid Prime")
    }

    func testPlayNextWithoutAlbumInheritsCurrent() {
        let p = seeded()
        p.playNext(makeTrack("trk_9", 9))
        XCTAssertEqual(p.queue[1].album.id, "alb_1")
    }

    func testPlayNextOnEmptyQueueIsIgnored() {
        let p = PlayerService()
        p.playNext(makeTrack("trk_9", 9))
        XCTAssertTrue(p.queue.isEmpty)
    }

    func testMoveInQueueFollowsTheCurrentTrack() {
        let p = seeded()
        XCTAssertEqual(p.queueIndex, 0)
        p.moveInQueue(from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(p.queueIndex, 1)
        XCTAssertEqual(p.currentTrack?.id, "trk_1")
    }

    func testRemoveBeforeCurrentShiftsIndex() {
        let p = seeded()
        let tracks = [makeTrack("trk_1", 1), makeTrack("trk_2", 2)]
        p.play(track: tracks[1], in: makeAlbum("alb_1", "Metroid Prime"), queue: tracks)
        XCTAssertEqual(p.queueIndex, 1)
        p.removeFromQueue(at: 0)
        XCTAssertEqual(p.queueIndex, 0)
        XCTAssertEqual(p.currentTrack?.id, "trk_2")
    }

    func testOnStateChangeFiresForQueueEdits() {
        let p = seeded()
        var fired = 0
        p.onStateChange = { _ in fired += 1 }

        p.playNext(makeTrack("trk_9", 9))
        p.isShuffle = true
        XCTAssertEqual(fired, 2)

        // Local UI, not playback state.
        p.showQueue = true
        XCTAssertEqual(fired, 2)
    }
}
