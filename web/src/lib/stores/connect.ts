import { writable, derived, get } from 'svelte/store';
import { api } from '$lib/api';
import type { Album, ConnectDevice, ConnectState } from '$lib/types';
import {
  player, playerNext, playerPrev, onPlayerStateChange, setRemoteSink,
  stopLocalPlayback, type PlayerState, type QueueItem,
} from './player';
import { addToast } from './toasts';

const DEVICE_ID_KEY = 'vgradio.deviceId';
const DEVICE_NAME_KEY = 'vgradio.deviceName';

/** Per tab, not per browser: two tabs sharing one ID would fight over the same
 * device slot and overwrite each other's state. */
function tabDeviceId(): string {
  let id = sessionStorage.getItem(DEVICE_ID_KEY);
  if (!id) {
    id = `web_${Math.random().toString(36).slice(2, 10)}`;
    sessionStorage.setItem(DEVICE_ID_KEY, id);
  }
  return id;
}

export const deviceName = writable(
  localStorage.getItem(DEVICE_NAME_KEY) ?? 'Navegador'
);
deviceName.subscribe(n => {
  if (typeof localStorage !== 'undefined') localStorage.setItem(DEVICE_NAME_KEY, n);
});

export const devices = writable<ConnectDevice[]>([]);
export const activeDeviceId = writable<string>('');
export const remoteState = writable<ConnectState | null>(null);
export const connected = writable(false);

export const deviceId = tabDeviceId();

/** True when another device owns playback: this tab renders and commands, but
 * plays no audio. */
export const isRemote = derived(
  activeDeviceId,
  $active => $active !== '' && $active !== deviceId
);

export const activeDevice = derived(
  [devices, activeDeviceId],
  ([$devices, $active]) => $devices.find(d => d.id === $active) ?? null
);

/** Other devices, for the picker. The picker hides itself when this is empty:
 * a lone device has nothing to connect to. */
export const otherDevices = derived(devices, $devices =>
  $devices.filter(d => d.id !== deviceId)
);

// ---------------------------------------------------------------- hydration

// Queue entries carry only IDs, so album metadata is fetched once per album and
// reused. Usually one or two albums are in play at a time.
const albumCache = new Map<string, Album>();
const albumsLoaded = writable(0); // bumped to re-run derived views after a fetch

async function hydrate(state: ConnectState | null) {
  const ids = new Set((state?.queue ?? []).map(q => q.albumId));
  let added = false;
  for (const id of ids) {
    if (albumCache.has(id)) continue;
    try {
      albumCache.set(id, await api.album(id));
      added = true;
    } catch {
      /* a missing album just renders without metadata */
    }
  }
  if (added) albumsLoaded.update(n => n + 1);
}

/** What the player bar renders while another device is playing. */
export const remoteView = derived(
  [remoteState, albumsLoaded],
  ([$state]) => {
    if (!$state) return null;
    const entries = $state.queue ?? [];
    const items = entries.map(e => {
      const album = albumCache.get(e.albumId);
      return {
        track: album?.tracks.find(t => t.id === e.trackId) ?? null,
        album: album ?? null,
        covers: album?.covers ?? [],
      };
    });
    return { state: $state, items, current: items[$state.queueIndex] ?? null };
  }
);

/** Position interpolated between state events, so the scrubber moves smoothly
 * without a network update per second. */
export const remotePosition = writable(0);

let ticker: ReturnType<typeof setInterval> | null = null;

function retick(state: ConnectState | null) {
  if (ticker) { clearInterval(ticker); ticker = null; }
  if (!state) { remotePosition.set(0); return; }
  const base = state.positionSec;
  const at = Date.parse(state.updatedAt);
  remotePosition.set(base);
  if (!state.isPlaying) return;
  ticker = setInterval(() => {
    remotePosition.set(base + (Date.now() - at) / 1000);
  }, 250);
}

// ---------------------------------------------------------------- transport

let source: EventSource | null = null;
let retry = 0;
let retryTimer: ReturnType<typeof setTimeout> | null = null;
let stopped = true;
let unsubscribePlayer: (() => void) | null = null;
let heartbeat: ReturnType<typeof setInterval> | null = null;

function applyDevices(list: ConnectDevice[]) {
  devices.set(list);
  const active = list.find(d => d.isActive);
  activeDeviceId.set(active?.id ?? '');
}

function onEvent(name: string, raw: string) {
  const data = JSON.parse(raw);
  switch (name) {
    case 'hello':
      applyDevices(data.devices ?? []);
      activeDeviceId.set(data.activeDeviceId ?? '');
      remoteState.set(data.state ?? null);
      hydrate(data.state);
      retick(data.state);
      break;
    case 'devices':
      applyDevices(data ?? []);
      break;
    case 'state':
      remoteState.set(data);
      hydrate(data);
      retick(data);
      break;
    case 'transfer':
      activeDeviceId.set(data.activeDeviceId ?? '');
      remoteState.set(data.state ?? null);
      retick(data.state);
      if (data.activeDeviceId && data.activeDeviceId !== deviceId) {
        stopLocalPlayback();
      } else if (data.activeDeviceId === deviceId) {
        adoptPlayback(data.state, data.play !== false);
      }
      break;
    case 'command':
      runCommand(data.type, data.payload);
      break;
  }
}

/** Executes a command addressed to this tab, by the same paths the local UI
 * uses. The remote sink is uninstalled while this runs, otherwise a command
 * would bounce straight back to the sender. */
function runCommand(type: string, payload: any) {
  const restore = get(isRemote);
  setRemoteSink(null);
  try {
    switch (type) {
      case 'toggle': player.togglePlay(); break;
      case 'play': if (!get(player).isPlaying) player.togglePlay(); break;
      case 'pause': if (get(player).isPlaying) player.togglePlay(); break;
      case 'next': playerNext(); break;
      case 'prev': playerPrev(); break;
      case 'seek': player.seek(payload?.positionSec ?? 0); break;
      case 'volume': player.setVolume(payload?.volume ?? 0.8); break;
      case 'mute': player.toggleMute(); break;
      case 'shuffle': player.toggleShuffle(); break;
      case 'repeat': player.cycleRepeat(); break;
      case 'playContext': playContext(payload); break;
      case 'queueRemove': player.removeFromQueue(payload?.index ?? -1); break;
      case 'queueMove': player.moveInQueue(payload?.from ?? 0, payload?.to ?? 0); break;
      case 'queueAdd': queueAdd(payload); break;
    }
  } finally {
    if (restore) installSink();
  }
}

/** Continues here what the previous device was playing: same queue, same track,
 * same position. Without this, "play here" would only move the crown and leave
 * the music stopped. */
async function adoptPlayback(state: ConnectState | null, play: boolean) {
  const entries = state?.queue ?? [];
  if (!state || entries.length === 0) return;

  await hydrate(state);

  const items: QueueItem[] = [];
  for (const e of entries) {
    const album = albumCache.get(e.albumId);
    const track = album?.tracks.find(t => t.id === e.trackId);
    if (album && track) items.push({ track, album: toSummary(album), covers: album.covers });
  }
  if (!items.length) return;

  const index = Math.min(Math.max(0, state.queueIndex), items.length - 1);
  player.adopt(items, index, state.positionSec, play);
}

async function playContext(payload: any) {
  if (!payload?.albumId) return;
  try {
    const album = await api.album(payload.albumId);
    const track = album.tracks.find(t => t.id === payload.startTrackId) ?? album.tracks[0];
    if (!track) return;
    player.play(track, toSummary(album), album.tracks, album.covers);
  } catch {
    addToast('No se pudo abrir el álbum pedido', 'error');
  }
}

async function queueAdd(payload: any) {
  if (!payload?.albumId || !payload?.trackId) return;
  try {
    const album = await api.album(payload.albumId);
    const track = album.tracks.find(t => t.id === payload.trackId);
    if (track) player.playNext(track, toSummary(album), album.covers);
  } catch {
    /* ignored: a queue add that fails is not worth interrupting playback for */
  }
}

function toSummary(a: Album) {
  return {
    id: a.id, title: a.title, platform: a.platform, year: a.year,
    albumType: a.albumType, trackCount: a.tracks.length,
    totalDurationSec: a.tracks.reduce((n, t) => n + t.durationSec, 0),
    coverUrls: a.covers.map(c => c.url),
  };
}

// ------------------------------------------------------------- publishing

function toWire(s: PlayerState): Partial<ConnectState> {
  return {
    isPlaying: s.isPlaying,
    positionSec: s.currentTime,
    volume: s.volume,
    isMuted: s.isMuted,
    isShuffle: s.isShuffle,
    repeatMode: s.repeatMode,
    queueIndex: s.queueIndex,
    coverIndex: s.currentCoverIndex,
    queue: s.queue.map(i => ({ trackId: i.track.id, albumId: i.album.id })),
  };
}

let publishTimer: ReturnType<typeof setTimeout> | null = null;

function publish(s: PlayerState) {
  if (get(activeDeviceId) !== deviceId) return;
  // Coalesce bursts (a track change fires several discrete updates in a row).
  if (publishTimer) clearTimeout(publishTimer);
  publishTimer = setTimeout(() => {
    api.publishState(deviceId, toWire(s)).catch(() => {});
  }, 150);
}

function installSink() {
  setRemoteSink((type, payload) => {
    if (!get(isRemote)) return false;
    api.sendCommand(deviceId, type, payload).catch(() => {
      addToast('No se pudo enviar el comando al otro dispositivo', 'error');
    });
    return true;
  });
}

// ---------------------------------------------------------------- lifecycle

export function startConnect() {
  if (!stopped) return;
  stopped = false;
  openStream();

  unsubscribePlayer = onPlayerStateChange(publish);
  installSink();

  // Keeps this device past the server-side TTL even when it publishes nothing.
  heartbeat = setInterval(() => {
    api.registerDevice({ id: deviceId, name: get(deviceName), type: 'web' }).catch(() => {});
  }, 20_000);

  // Best-effort clean exit so the device disappears from other pickers at once
  // instead of waiting out the TTL.
  window.addEventListener('pagehide', unregisterBeacon);
}

function unregisterBeacon() {
  api.unregisterDevice(deviceId).catch(() => {});
}

function openStream() {
  if (stopped) return;
  source?.close();
  source = new EventSource(api.connectEventsURL(deviceId, get(deviceName)), {
    withCredentials: true,
  });

  for (const name of ['hello', 'devices', 'state', 'transfer', 'command']) {
    source.addEventListener(name, e => {
      try {
        onEvent(name, (e as MessageEvent).data);
      } catch (err) {
        console.error('[connect] bad event', name, err);
      }
    });
  }

  source.onopen = () => { retry = 0; connected.set(true); };
  source.onerror = () => {
    connected.set(false);
    source?.close();
    source = null;
    if (stopped) return;
    // Exponential backoff, capped: a backend restart should not turn into a
    // reconnect storm from every open tab.
    const delay = Math.min(30_000, 1000 * 2 ** retry++);
    retryTimer = setTimeout(openStream, delay);
  };
}

export function stopConnect() {
  stopped = true;
  if (retryTimer) { clearTimeout(retryTimer); retryTimer = null; }
  if (heartbeat) { clearInterval(heartbeat); heartbeat = null; }
  if (ticker) { clearInterval(ticker); ticker = null; }
  unsubscribePlayer?.();
  unsubscribePlayer = null;
  setRemoteSink(null);
  window.removeEventListener('pagehide', unregisterBeacon);
  source?.close();
  source = null;
  connected.set(false);
  devices.set([]);
  activeDeviceId.set('');
  remoteState.set(null);
  retry = 0;
}

/** Moves playback to a device, or takes it over locally. */
export async function transferTo(id: string, play = true) {
  try {
    await api.transferPlayback(id, play);
    if (id !== deviceId) stopLocalPlayback();
  } catch {
    addToast('No se pudo cambiar de dispositivo', 'error');
  }
}
