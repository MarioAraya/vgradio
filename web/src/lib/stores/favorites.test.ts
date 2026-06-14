import { describe, it, expect, beforeEach, vi } from 'vitest';
import { get } from 'svelte/store';

beforeEach(() => {
  localStorage.clear();
  vi.resetModules();
});

async function fresh() {
  return import('./favorites');
}

const track = (id = 'track-1') => ({
  id, name: `Track ${id}`, index: 0, durationSec: 180,
  sizeBytes: 0, streamUrl: '', downloadUrl: '', downloaded: false,
});
const album = (id = 'album-1') => ({
  id, title: `Album ${id}`, platform: 'SNES', year: 1993,
  albumType: 'OST', trackCount: 10, coverUrls: ['/covers/album-1/cover_0.jpg'],
});

describe('favorites store', () => {
  it('starts empty', async () => {
    const { favorites } = await fresh();
    expect(get(favorites)).toHaveLength(0);
  });

  it('toggle adds a track', async () => {
    const { favorites } = await fresh();
    favorites.toggle(track(), album());
    expect(get(favorites)).toHaveLength(1);
    expect(get(favorites)[0].id).toBe('track-1');
  });

  it('toggle removes an existing track', async () => {
    const { favorites } = await fresh();
    favorites.toggle(track(), album());
    favorites.toggle(track(), album());
    expect(get(favorites)).toHaveLength(0);
  });

  it('stores coverUrl from album', async () => {
    const { favorites } = await fresh();
    favorites.toggle(track(), album());
    expect(get(favorites)[0].coverUrl).toBe('/covers/album-1/cover_0.jpg');
  });

  it('addAll adds all tracks, skipping duplicates', async () => {
    const { favorites } = await fresh();
    favorites.addAll([track('t1'), track('t2'), track('t3')], album());
    expect(get(favorites)).toHaveLength(3);
    favorites.addAll([track('t2'), track('t4')], album());
    expect(get(favorites)).toHaveLength(4);
  });

  it('removeAll removes by albumId', async () => {
    const { favorites } = await fresh();
    favorites.addAll([track('t1'), track('t2')], album('a1'));
    favorites.addAll([track('t3')], album('a2'));
    favorites.removeAll('a1');
    const left = get(favorites);
    expect(left).toHaveLength(1);
    expect(left[0].albumId).toBe('a2');
  });
});

describe('favoritesGrouped', () => {
  it('groups by albumId', async () => {
    const { favorites, favoritesGrouped } = await fresh();
    favorites.addAll([track('t1'), track('t2')], album('a1'));
    favorites.addAll([track('t3')], album('a2'));
    const groups = get(favoritesGrouped);
    expect(groups).toHaveLength(2);
    expect(groups[0].tracks).toHaveLength(2);
    expect(groups[1].tracks).toHaveLength(1);
  });
});
