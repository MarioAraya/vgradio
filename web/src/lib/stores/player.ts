import { writable, get } from 'svelte/store';
import type { Track, AlbumSummary, Cover } from '$lib/types';
import { api } from '$lib/api';
import { hidden } from './hidden';
import { addToast } from './toasts';

export type RepeatMode = 'off' | 'all' | 'one';

// Each queue entry carries its own album/covers so a track queued from a
// different album (via "Play Next") shows its own cover and album title
// instead of whatever album the queue happened to start from.
export interface QueueItem {
  track: Track;
  album: AlbumSummary;
  covers: Cover[];
}

interface PlayerState {
  queue: QueueItem[];
  queueIndex: number;
  queuedEnd: number; // last index of manually-queued tracks; resets on track change
  currentCoverIndex: number;
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  volume: number;
  isMuted: boolean;
  isShuffle: boolean;
  repeatMode: RepeatMode;
  showQueue: boolean;
}

const initial: PlayerState = {
  queue: [], queueIndex: 0, queuedEnd: 0,
  currentCoverIndex: 0,
  isPlaying: false, currentTime: 0, duration: 0,
  volume: parseFloat(localStorage.getItem('vgradio.volume') ?? '0.8'),
  isMuted: false, isShuffle: false, repeatMode: 'off',
  showQueue: false,
};

const { subscribe, update, set } = writable<PlayerState>(initial);

let audio: HTMLAudioElement | null = null;

function getAudio(): HTMLAudioElement {
  if (!audio) {
    audio = new Audio();
    audio.addEventListener('timeupdate', () => {
      update(s => ({ ...s, currentTime: audio!.currentTime }));
    });
    audio.addEventListener('loadedmetadata', () => {
      update(s => ({ ...s, duration: audio!.duration || s.duration }));
    });
    audio.addEventListener('ended', () => next());
    audio.addEventListener('play', () => {
      update(s => ({ ...s, isPlaying: true }));
      updateMediaSessionState(true);
    });
    audio.addEventListener('pause', () => {
      update(s => ({ ...s, isPlaying: false }));
      updateMediaSessionState(false);
    });
    audio.addEventListener('error', async () => {
      const a = getAudio();
      const s = get({ subscribe });
      const track = s.queue[s.queueIndex]?.track;
      if (!track) { addToast('Error al descargar la canción', 'error'); next(); return; }

      if (a.src.includes('/stream')) {
        // First failure: try cached direct URL from khinsider
        try {
          const { url } = await api.resolveTrackUrl(track.id, false);
          if (url) { fallbackAttempted.add(track.id); a.src = url; a.play().catch(() => {}); return; }
        } catch { /* fall through */ }
      } else if (fallbackAttempted.has(track.id)) {
        // Second failure: cached URL is stale — force re-scrape
        fallbackAttempted.delete(track.id);
        try {
          const { url } = await api.resolveTrackUrl(track.id, true);
          if (url) { a.src = url; a.play().catch(() => {}); return; }
        } catch { /* fall through */ }
      }

      addToast('Error al descargar la canción', 'error');
      next();
    });
    if (!mediaSessionReady) {
      setupMediaSession();
      mediaSessionReady = true;
    }
  }
  return audio;
}

function isHidden(item: QueueItem): boolean {
  return get(hidden).has(item.track.id);
}

function setupMediaSession() {
  if (!('mediaSession' in navigator)) return;
  navigator.mediaSession.setActionHandler('play', () => {
    getAudio().play().catch(() => {});
  });
  navigator.mediaSession.setActionHandler('pause', () => {
    getAudio().pause();
  });
  navigator.mediaSession.setActionHandler('nexttrack', () => next());
  navigator.mediaSession.setActionHandler('previoustrack', () => playerPrev());
  navigator.mediaSession.setActionHandler('seekto', (e) => {
    if (e.seekTime != null) player.seek(e.seekTime);
  });
  navigator.mediaSession.setActionHandler('seekbackward', (e) => {
    player.seek(Math.max(0, getAudio().currentTime - (e.seekOffset ?? 10)));
  });
  navigator.mediaSession.setActionHandler('seekforward', (e) => {
    const a = getAudio();
    player.seek(Math.min(a.duration || Infinity, a.currentTime + (e.seekOffset ?? 10)));
  });
}

function updateMediaSessionMetadata(state: PlayerState) {
  if (!('mediaSession' in navigator)) return;
  const item = state.queue[state.queueIndex];
  if (!item) return;
  const cover = item.covers[state.currentCoverIndex] ?? item.covers[0];
  const artwork: MediaImage[] = cover
    ? [{ src: api.coverURL(cover.url), sizes: '400x400', type: 'image/jpeg' }]
    : [];
  navigator.mediaSession.metadata = new MediaMetadata({
    title: item.track.name,
    album: item.album.title,
    artwork,
  });
}

function updateMediaSessionState(playing: boolean) {
  if (!('mediaSession' in navigator)) return;
  navigator.mediaSession.playbackState = playing ? 'playing' : 'paused';
}

let mediaSessionReady = false;
const fallbackAttempted = new Set<string>(); // trackIds where direct-URL fallback was tried

function loadTrack(state: PlayerState): PlayerState {
  const item = state.queue[state.queueIndex];
  if (!item) return state;
  const { track, album } = item;
  fallbackAttempted.delete(track.id);
  const a = getAudio();
  a.pause();
  a.src = api.streamURL(track);
  a.volume = state.isMuted ? 0 : state.volume;
  a.load();
  a.play().catch(() => {});
  api.recordPlay(track.id, album.id).catch(() => {});
  const next = { ...state, currentTime: 0, duration: track.durationSec };
  updateMediaSessionMetadata(next);
  return next;
}

export const player = {
  subscribe,

  play(track: Track, album: AlbumSummary, queue: Track[], covers: Cover[] = []) {
    update(s => {
      const idx = queue.findIndex(t => t.id === track.id);
      const qi = idx >= 0 ? idx : 0;
      const items: QueueItem[] = queue.map(t => ({ track: t, album, covers }));
      const prevAlbumId = s.queue[s.queueIndex]?.album.id;
      const next: PlayerState = {
        ...s, queue: items, queueIndex: qi, queuedEnd: qi,
        currentCoverIndex: prevAlbumId === album.id ? s.currentCoverIndex : 0,
      };
      return loadTrack(next);
    });
  },

  togglePlay() {
    const a = getAudio();
    if (!a.src) return;
    a.paused ? a.play().catch(() => {}) : a.pause();
  },

  seek(secs: number) {
    const a = getAudio();
    a.currentTime = secs;
    update(s => ({ ...s, currentTime: secs }));
  },

  setVolume(v: number) {
    const a = getAudio();
    a.volume = v;
    localStorage.setItem('vgradio.volume', String(v));
    update(s => ({ ...s, volume: v, isMuted: v === 0 ? true : s.isMuted }));
  },

  toggleMute() {
    update(s => {
      const a = getAudio();
      const muted = !s.isMuted;
      a.volume = muted ? 0 : s.volume;
      return { ...s, isMuted: muted };
    });
  },

  /** Inserts track right after the current queue position, using the album/covers
   * of whatever is currently playing (or the caller's, if the queue is empty). */
  playNext(track: Track, album?: AlbumSummary, covers: Cover[] = []) {
    update(s => {
      const fallback = s.queue[s.queueIndex];
      const itemAlbum = album ?? fallback?.album;
      if (!itemAlbum) return s;
      const q = [...s.queue];
      const insertAt = s.queuedEnd + 1;
      q.splice(insertAt, 0, { track, album: itemAlbum, covers: album ? covers : fallback?.covers ?? [] });
      return { ...s, queue: q, queuedEnd: insertAt };
    });
  },

  removeFromQueue(index: number) {
    update(s => {
      const q = [...s.queue];
      q.splice(index, 1);
      let qi = s.queueIndex;
      if (index < qi) qi--;
      else if (index === qi) qi = Math.min(qi, q.length - 1);
      return { ...s, queue: q, queueIndex: qi };
    });
  },

  moveInQueue(from: number, to: number) {
    update(s => {
      const q = [...s.queue];
      const [item] = q.splice(from, 1);
      q.splice(to, 0, item);
      const currentId = s.queue[s.queueIndex]?.track.id;
      const qi = q.findIndex(it => it.track.id === currentId);
      return { ...s, queue: q, queueIndex: qi >= 0 ? qi : s.queueIndex };
    });
  },

  setCoverIndex(albumId: string, index: number) {
    update(s => {
      if (s.queue[s.queueIndex]?.album.id !== albumId) return s;
      return { ...s, currentCoverIndex: index };
    });
  },

  toggleQueue() {
    update(s => {
      const showQueue = !s.showQueue;
      localStorage.setItem('vgradio.showQueue', String(showQueue));
      return { ...s, showQueue };
    });
  },
  toggleShuffle() { update(s => ({ ...s, isShuffle: !s.isShuffle })); },
  cycleRepeat() {
    update(s => {
      const modes: RepeatMode[] = ['off', 'all', 'one'];
      const next = modes[(modes.indexOf(s.repeatMode) + 1) % 3];
      return { ...s, repeatMode: next };
    });
  },
};

function next() {
  const s = get({ subscribe });
  if (s.queue.length === 0) return;
  if (s.repeatMode === 'one') {
    player.seek(0);
    getAudio().play().catch(() => {});
    return;
  }
  if (s.isShuffle) {
    const candidates = s.queue.map((_, i) => i).filter(i => i !== s.queueIndex && !isHidden(s.queue[i]));
    if (!candidates.length) return;
    const idx = candidates[Math.floor(Math.random() * candidates.length)];
    update(state => loadTrack(advance(state, idx)));
    return;
  }
  let idx = s.queueIndex + 1;
  while (idx < s.queue.length && isHidden(s.queue[idx])) idx++;
  if (idx >= s.queue.length) {
    if (s.repeatMode !== 'all') return;
    idx = 0;
    while (idx < s.queue.length && isHidden(s.queue[idx])) idx++;
    if (idx >= s.queue.length) return;
  }
  update(state => loadTrack(advance(state, idx)));
}

// Moves to queue index `idx`, resetting the cover picker when the new track
// belongs to a different album than the one currently playing.
function advance(state: PlayerState, idx: number): PlayerState {
  const prevAlbumId = state.queue[state.queueIndex]?.album.id;
  const nextAlbumId = state.queue[idx]?.album.id;
  return {
    ...state, queueIndex: idx, queuedEnd: idx,
    currentCoverIndex: prevAlbumId === nextAlbumId ? state.currentCoverIndex : 0,
  };
}

export function playerNext() { next(); }

export function playerPrev() {
  const s = get({ subscribe });
  const a = getAudio();
  if (a.currentTime > 3) { player.seek(0); return; }
  let idx = s.queueIndex - 1;
  while (idx >= 0 && isHidden(s.queue[idx])) idx--;
  if (idx < 0) return;
  update(state => loadTrack(advance(state, idx)));
}
