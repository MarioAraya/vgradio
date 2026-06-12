import { writable, derived } from 'svelte/store';
import type { FavoriteTrack, Track, AlbumSummary } from '$lib/types';

const KEY = 'vgradio.favorites';

function load(): FavoriteTrack[] {
  try { return JSON.parse(localStorage.getItem(KEY) ?? '[]'); } catch { return []; }
}

function save(items: FavoriteTrack[]) {
  localStorage.setItem(KEY, JSON.stringify(items));
}

const { subscribe, update, set } = writable<FavoriteTrack[]>(load());

export const favorites = {
  subscribe,
  isFavorite: (id: string) => {
    let found = false;
    favorites.subscribe(items => { found = items.some(f => f.id === id); })();
    return found;
  },
  toggle(track: Track, album: AlbumSummary) {
    update(items => {
      const next = items.some(f => f.id === track.id)
        ? items.filter(f => f.id !== track.id)
        : [...items, { id: track.id, name: track.name, albumId: album.id, albumTitle: album.title, platform: album.platform, year: album.year, durationSec: track.durationSec }];
      save(next); return next;
    });
  },
  addAll(tracks: Track[], album: AlbumSummary) {
    update(items => {
      const ids = new Set(items.map(f => f.id));
      const next = [...items, ...tracks.filter(t => !ids.has(t.id)).map(t => ({
        id: t.id, name: t.name, albumId: album.id, albumTitle: album.title,
        platform: album.platform, year: album.year, durationSec: t.durationSec,
      }))];
      save(next); return next;
    });
  },
  removeAll(albumId: string) {
    update(items => { const next = items.filter(f => f.albumId !== albumId); save(next); return next; });
  },
};

export const favoritesGrouped = derived(favorites, $fav => {
  const map = new Map<string, { albumTitle: string; platform: string; year: number; tracks: FavoriteTrack[] }>();
  for (const f of $fav) {
    if (!map.has(f.albumId)) map.set(f.albumId, { albumTitle: f.albumTitle, platform: f.platform, year: f.year, tracks: [] });
    map.get(f.albumId)!.tracks.push(f);
  }
  return [...map.values()];
});
