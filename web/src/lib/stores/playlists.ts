import { writable, get } from 'svelte/store';
import { api } from '$lib/api';
import type { PlaylistSummary, PlaylistDetail } from '$lib/types';

export const playlists = writable<PlaylistSummary[]>([]);
export const playlistsLoading = writable(false);

export async function loadPlaylists() {
  playlistsLoading.set(true);
  try {
    const list = await api.playlists();
    playlists.set(list);
  } catch {
    // not logged in or network error — keep empty
  } finally {
    playlistsLoading.set(false);
  }
}

export async function createPlaylist(name: string, description = '', isPublic = false): Promise<PlaylistSummary> {
  const pl = await api.createPlaylist(name, description, isPublic);
  playlists.update(list => [pl, ...list]);
  return pl;
}

export async function updatePlaylist(id: string, data: Partial<{ name: string; description: string; isPublic: boolean }>) {
  await api.updatePlaylist(id, data);
  playlists.update(list =>
    list.map(p => p.id === id ? { ...p, ...data } : p)
  );
}

export async function deletePlaylist(id: string) {
  await api.deletePlaylist(id);
  playlists.update(list => list.filter(p => p.id !== id));
}

export async function addTrackToPlaylist(playlistId: string, trackId: string) {
  await api.addTrackToPlaylist(playlistId, trackId);
  // bump trackCount optimistically
  playlists.update(list =>
    list.map(p => p.id === playlistId ? { ...p, trackCount: p.trackCount + 1 } : p)
  );
}

export async function removeTrackFromPlaylist(playlistId: string, trackId: string) {
  await api.removeTrackFromPlaylist(playlistId, trackId);
  playlists.update(list =>
    list.map(p => p.id === playlistId ? { ...p, trackCount: Math.max(0, p.trackCount - 1) } : p)
  );
}

export function myPlaylists(userId: string) {
  return get(playlists).filter(p => p.ownerId === userId);
}
