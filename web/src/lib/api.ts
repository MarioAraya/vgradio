import type {
  Album, AlbumSummary, CatalogConsole, CatalogPage,
  CatalogSyncProgress, HistoryEntry, ScrapeJob, Track
} from './types';

const BASE = () =>
  localStorage.getItem('vgradio.backendURL') ??
  `http://${typeof window !== 'undefined' ? window.location.hostname : 'localhost'}:8080`;

async function get<T>(path: string): Promise<T> {
  const r = await fetch(BASE() + path);
  if (!r.ok) throw new Error(`GET ${path} → ${r.status}`);
  return r.json();
}

async function post<T>(path: string, body?: unknown): Promise<T> {
  const r = await fetch(BASE() + path, {
    method: 'POST',
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
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
  album: (id: string) => get<Album>(`/albums/${id}`),
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
  catalogSyncProgress: () => get<CatalogSyncProgress>('/catalog/sync'),

  recordPlay: (trackId: string, albumId: string) =>
    post<void>('/history', { trackId, albumId }),
  history: (limit = 100) => get<HistoryEntry[]>(`/history?limit=${limit}`),

  fetchTrack: (trackId: string) => post<{ status: string; localPath: string }>(`/tracks/${trackId}/fetch`),
  streamURL: (track: Track) => BASE() + track.streamUrl,
  downloadURL: (track: Track) => BASE() + track.downloadUrl,
  coverURL: (url: string) => url.startsWith('http') ? url : BASE() + url,
};

export async function pollJob(jobId: string, onDone: (albumId: string) => void) {
  while (true) {
    const job = await api.job(jobId);
    if (job.status === 'done') { onDone(job.albumId); return; }
    if (job.status === 'failed') throw new Error(job.error ?? 'scrape failed');
    await new Promise(r => setTimeout(r, 800));
  }
}
