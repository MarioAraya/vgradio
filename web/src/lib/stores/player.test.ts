import { describe, it, expect, vi } from 'vitest';
import { player, onPlayerStateChange } from './player';
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
