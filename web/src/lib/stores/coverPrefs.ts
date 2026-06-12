import { writable } from 'svelte/store';

const KEY = 'vgradio.coverPrefs';

function load(): Record<string, number> {
  try { return JSON.parse(localStorage.getItem(KEY) ?? '{}'); } catch { return {}; }
}

const { subscribe, update } = writable<Record<string, number>>(load());

export const coverPrefs = {
  subscribe,
  get(albumId: string): number {
    let v = 0;
    coverPrefs.subscribe(p => { v = p[albumId] ?? 0; })();
    return v;
  },
  set(albumId: string, index: number) {
    update(p => {
      const next = { ...p, [albumId]: index };
      localStorage.setItem(KEY, JSON.stringify(next));
      return next;
    });
  },
};
