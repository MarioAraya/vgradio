import { describe, it, expect, vi, afterEach } from 'vitest';
import { get } from 'svelte/store';
import {
  player, onPlayerStateChange, setRemoteSink, playerNext, playerPrev,
} from './player';
import type { Track, AlbumSummary } from '$lib/types';

const track = (id: string, index: number): Track => ({
  id, index, name: `Track ${index}`, durationSec: 100, sizeBytes: 1000,
  streamUrl: `/tracks/${id}/stream`, downloadUrl: `/tracks/${id}/download`,
  downloaded: false,
});

const album: AlbumSummary = {
  id: 'alb_1', title: 'Metroid Prime', platform: 'GC', year: 2002,
  albumType: 'Gamerip', trackCount: 2, totalDurationSec: 200, coverUrls: [],
};

describe('onPlayerStateChange', () => {
  it('notifies on discrete changes and stops after unsubscribe', () => {
    const seen = vi.fn();
    const off = onPlayerStateChange(seen);

    const tracks = [track('trk_1', 1), track('trk_2', 2)];
    player.play(tracks[0], album, tracks);
    expect(seen).toHaveBeenCalledTimes(1);
    expect(seen.mock.lastCall![0].queue).toHaveLength(2);

    player.seek(42);
    player.toggleShuffle();
    expect(seen).toHaveBeenCalledTimes(3);

    off();
    player.toggleShuffle();
    expect(seen).toHaveBeenCalledTimes(3);
  });

  it('ignores queue-panel visibility, which is local UI and not playback state', () => {
    const seen = vi.fn();
    const off = onPlayerStateChange(seen);
    player.toggleQueue();
    expect(seen).not.toHaveBeenCalled();
    off();
  });
});

describe('remote sink', () => {
  afterEach(() => setRemoteSink(null));

  // Every control must consult the sink. A single missed guard means one button
  // silently plays here instead of on the device the user is controlling.
  it('routes every control through the sink instead of acting locally', () => {
    const tracks = [track('trk_1', 1), track('trk_2', 2)];
    player.play(tracks[0], album, tracks);

    const sent: string[] = [];
    setRemoteSink(type => { sent.push(type); return true; });

    const before = get(player);

    player.play(tracks[1], album, tracks);
    player.togglePlay();
    player.seek(10);
    player.setVolume(0.3);
    player.toggleMute();
    player.playNext(track('trk_9', 9));
    player.removeFromQueue(0);
    player.moveInQueue(0, 1);
    player.toggleShuffle();
    player.cycleRepeat();
    playerNext();
    playerPrev();

    expect(sent).toEqual([
      'playContext', 'toggle', 'seek', 'volume', 'mute', 'queueAdd',
      'queueRemove', 'queueMove', 'shuffle', 'repeat', 'next', 'prev',
    ]);

    // Nothing was applied locally.
    const after = get(player);
    expect(after.queue).toHaveLength(before.queue.length);
    expect(after.queueIndex).toBe(before.queueIndex);
    expect(after.isShuffle).toBe(before.isShuffle);
    expect(after.repeatMode).toBe(before.repeatMode);
  });

  it('acts locally again once the sink declines', () => {
    setRemoteSink(() => false);
    const before = get(player).isShuffle;
    player.toggleShuffle();
    expect(get(player).isShuffle).toBe(!before);
  });
});
