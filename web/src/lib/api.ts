import type {
  Album, AlbumSummary, CatalogConsole, CatalogPage,
  CatalogSyncProgress, DownloadedAlbum, HistoryEntry, LibraryStats, ScrapeJob, Track, User,
  PlaylistSummary, PlaylistDetail
} from './types';

const BASE = () =>
  localStorage.getItem('vgradio.backendURL') ??
  (import.meta.env.VITE_API_URL as string | undefined) ??
  `http://${typeof window !== 'undefined' ? window.location.hostname : 'localhost'}:8080`;

async function get<T>(path: string, signal?: AbortSignal): Promise<T> {
  const r = await fetch(BASE() + path, { signal, credentials: 'include' });
  if (!r.ok) throw new Error(`GET ${path} → ${r.status}`);
  return r.json();
}

async function del<T>(path: string): Promise<T> {
  const r = await fetch(BASE() + path, { method: 'DELETE', credentials: 'include' });
  if (!r.ok) throw new Error(`DELETE ${path} → ${r.status}`);
  if (r.status === 204 || r.headers.get('content-length') === '0') return undefined as T;
  return r.json();
}

async function patch<T>(path: string, body?: unknown): Promise<T> {
  const r = await fetch(BASE() + path, {
    method: 'PATCH',
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
    credentials: 'include',
  });
  if (!r.ok) {
    const err = await r.json().catch(() => ({ error: r.statusText }));
    throw new Error(err.error ?? r.statusText);
  }
  if (r.status === 204 || r.headers.get('content-length') === '0') return undefined as T;
  return r.json();
}

async function put<T>(path: string, body?: unknown): Promise<T> {
  const r = await fetch(BASE() + path, {
    method: 'PUT',
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
    credentials: 'include',
  });
  if (!r.ok) {
    const err = await r.json().catch(() => ({ error: r.statusText }));
    throw new Error(err.error ?? r.statusText);
  }
  if (r.status === 204 || r.headers.get('content-length') === '0') return undefined as T;
  return r.json();
}

async function post<T>(path: string, body?: unknown, signal?: AbortSignal): Promise<T> {
  const r = await fetch(BASE() + path, {
    method: 'POST',
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
    signal,
    credentials: 'include',
  });
  if (!r.ok && r.status !== 409) {
    const err = await r.json().catch(() => ({ error: r.statusText }));
    throw new Error(err.error ?? r.statusText);
  }
  if (r.status === 204 || r.headers.get('content-length') === '0') return undefined as T;
  return r.json();
}

export const api = {
  baseURL: BASE,
  albums: () => get<AlbumSummary[]>('/albums'),
  album: (id: string, signal?: AbortSignal) => get<Album>(`/albums/${id}`, signal),
  addAlbum: (url: string) => post<ScrapeJob>('/albums', { url }),
  job: (id: string) => get<ScrapeJob>(`/jobs/${id}`),

  catalog: (params: { q?: string; platform?: string; letter?: string; offset?: number; limit?: number }) => {
    const p = new URLSearchParams();
    if (params.q) p.set('q', params.q);
    if (params.platform) p.set('platform', params.platform);
    if (params.letter) p.set('letter', params.letter);
    if (params.offset) p.set('offset', String(params.offset));
    p.set('limit', String(params.limit ?? 50));
    return get<CatalogPage>(`/catalog?${p}`);
  },
  catalogConsoles: () => get<CatalogConsole[]>('/catalog/consoles'),
  startCatalogSync: () => post<void>('/catalog/sync'),
  startLetterSync: (letter: string) => post<{ status: string; letter: string }>(`/catalog/sync?letter=${encodeURIComponent(letter)}`),
  catalogSyncProgress: () => get<CatalogSyncProgress>('/catalog/sync'),

  recordPlay: (trackId: string, albumId: string) =>
    post<void>('/history', { trackId, albumId }),
  history: (limit = 100) => get<HistoryEntry[]>(`/history?limit=${limit}`),

  scrapeAlbumTracks: (albumId: string) =>
    post<{ resolved: number; failed: number; skipped: number }>(`/albums/${albumId}/scrape-tracks`),
  fetchTrack: (trackId: string, signal?: AbortSignal) =>
    post<{ status: string; localPath: string }>(`/tracks/${trackId}/fetch`, undefined, signal),
  resolveTrackUrl: (trackId: string, force = false) =>
    get<{ url: string }>(`/tracks/${trackId}/resolve${force ? '?force=1' : ''}`),
  setCFClearance: (value: string) =>
    fetch(BASE() + '/config/cf-clearance', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ value }),
    }).then(r => r.json()),

  stats: () => get<LibraryStats>('/stats'),
  downloadedAlbums: () => get<DownloadedAlbum[]>('/albums/downloaded'),
  deleteAlbumLocal: (albumId: string) => del<{ deleted: number }>(`/albums/${albumId}/local`),
  scrapeAllPending: () => post<{ resolved: number; failed: number; total: number }>('/scrape/pending'),

  streamURL: (track: Track) => BASE() + track.streamUrl,
  downloadURL: (track: Track) => BASE() + track.downloadUrl,
  coverURL: (url: string) => url.startsWith('http') ? url : BASE() + url,

  // auth
  register: (username: string, email: string, password: string) =>
    post<User>('/auth/register', { username, email, password }),
  login: (email: string, password: string) =>
    post<User>('/auth/login', { email, password }),
  logout: () => post<void>('/auth/logout'),
  me: () => get<User | null>('/auth/me'),

  // album favorites
  toggleFavorite: (albumId: string) =>
    post<{ favorited: boolean }>(`/favorites/${albumId}`),
  favorites: () => get<AlbumSummary[]>('/favorites'),
  // track favorites
  toggleTrackFavorite: (trackId: string) =>
    post<{ favorited: boolean }>(`/favorites/tracks/${trackId}`),
  favoriteTracks: () => get<import('$lib/types').FavoriteTrack[]>('/favorites/tracks'),

  // playlists
  playlists: () => get<PlaylistSummary[]>('/playlists'),
  playlist: (id: string) => get<PlaylistDetail>(`/playlists/${id}`),
  createPlaylist: (name: string, description: string, isPublic: boolean) =>
    post<PlaylistSummary>('/playlists', { name, description, isPublic }),
  updatePlaylist: (id: string, data: Partial<{ name: string; description: string; isPublic: boolean }>) =>
    patch<void>(`/playlists/${id}`, data),
  deletePlaylist: (id: string) => del<void>(`/playlists/${id}`),
  addTrackToPlaylist: (playlistId: string, trackId: string) =>
    post<void>(`/playlists/${playlistId}/tracks`, { trackId }),
  removeTrackFromPlaylist: (playlistId: string, trackId: string) =>
    del<void>(`/playlists/${playlistId}/tracks/${trackId}`),
  reorderPlaylistTracks: (playlistId: string, items: { trackId: string; position: number }[]) =>
    put<void>(`/playlists/${playlistId}/tracks/reorder`, items),
};

export async function pollJob(jobId: string, onDone: (albumId: string) => void) {
  while (true) {
    const job = await api.job(jobId);
    if (job.status === 'done') { onDone(job.albumId); return; }
    if (job.status === 'failed') throw new Error(job.error ?? 'scrape failed');
    await new Promise(r => setTimeout(r, 800));
  }
}
