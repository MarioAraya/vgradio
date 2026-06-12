import { writable, get } from 'svelte/store';
import type { Track, AlbumSummary, Cover } from '$lib/types';
import { api } from '$lib/api';
import { hidden } from './hidden';
import { addToast } from './toasts';

export type RepeatMode = 'off' | 'all' | 'one';

interface PlayerState {
  queue: Track[];
  queueIndex: number;
  currentAlbum: AlbumSummary | null;
  currentCovers: Cover[];
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
  queue: [], queueIndex: 0,
  currentAlbum: null, currentCovers: [], currentCoverIndex: 0,
  isPlaying: false, currentTime: 0, duration: 0,
  volume: parseFloat(localStorage.getItem('vgradio.volume') ?? '0.8'),
  isMuted: false, isShuffle: false, repeatMode: 'off',
  showQueue: localStorage.getItem('vgradio.showQueue') === 'true',
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
    audio.addEventListener('play', () => update(s => ({ ...s, isPlaying: true })));
    audio.addEventListener('pause', () => update(s => ({ ...s, isPlaying: false })));
    audio.addEventListener('error', () => {
      addToast('Error al descargar la canción', 'error');
      next();
    });
  }
  return audio;
}

function isHidden(track: Track): boolean {
  return get(hidden).has(track.id);
}

function loadTrack(state: PlayerState): PlayerState {
  const track = state.queue[state.queueIndex];
  if (!track) return state;
  const a = getAudio();
  a.pause();
  a.src = api.streamURL(track);
  a.volume = state.isMuted ? 0 : state.volume;
  a.load();
  a.play().catch(() => {});
  if (state.currentAlbum) {
    api.recordPlay(track.id, state.currentAlbum.id).catch(() => {});
  }
  return { ...state, currentTime: 0, duration: track.durationSec };
}

export const player = {
  subscribe,

  play(track: Track, album: AlbumSummary, queue: Track[], covers: Cover[] = []) {
    update(s => {
      const idx = queue.findIndex(t => t.id === track.id);
      const next: PlayerState = { ...s, queue, queueIndex: idx >= 0 ? idx : 0, currentAlbum: album, currentCovers: covers, currentCoverIndex: s.currentAlbum?.id === album.id ? s.currentCoverIndex : 0 };
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

  playNext(track: Track) {
    update(s => {
      const q = [...s.queue];
      q.splice(s.queueIndex + 1, 0, track);
      return { ...s, queue: q };
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
      const currentId = s.queue[s.queueIndex]?.id;
      const qi = q.findIndex(t => t.id === currentId);
      return { ...s, queue: q, queueIndex: qi >= 0 ? qi : s.queueIndex };
    });
  },

  setCoverIndex(albumId: string, index: number) {
    update(s => {
      if (s.currentAlbum?.id !== albumId) return s;
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
    update(state => loadTrack({ ...state, queueIndex: idx }));
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
  update(state => loadTrack({ ...state, queueIndex: idx }));
}

export function playerNext() { next(); }

export function playerPrev() {
  const s = get({ subscribe });
  const a = getAudio();
  if (a.currentTime > 3) { player.seek(0); return; }
  let idx = s.queueIndex - 1;
  while (idx >= 0 && isHidden(s.queue[idx])) idx--;
  if (idx < 0) return;
  update(state => loadTrack({ ...state, queueIndex: idx }));
}
