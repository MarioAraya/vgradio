import { writable, get } from 'svelte/store';
import { api } from '$lib/api';

export const favoritedTrackIDs = writable<Set<string>>(new Set());

// Tracks changes made before initTrackFavorites completes, so the
// server response doesn't overwrite them.
const pendingToggles = new Map<string, boolean>();
let initDone = false;

export async function initTrackFavorites(): Promise<void> {
  try {
    const tracks = await api.favoriteTracks();
    favoritedTrackIDs.update(() => {
      const merged = new Set(tracks.map(t => t.id));
      // Apply any toggles the user made while the request was in flight
      for (const [id, fav] of pendingToggles) {
        if (fav) merged.add(id);
        else merged.delete(id);
      }
      pendingToggles.clear();
      return merged;
    });
  } catch {
    pendingToggles.clear();
  } finally {
    initDone = true;
  }
}

export function setTrackFavorited(trackId: string, favorited: boolean): void {
  if (!initDone) pendingToggles.set(trackId, favorited);
  favoritedTrackIDs.update(s => {
    const next = new Set(s);
    if (favorited) next.add(trackId);
    else next.delete(trackId);
    return next;
  });
}
