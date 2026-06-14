import { writable } from 'svelte/store';

const KEY = 'vgradio.hiddenTracks';

function load(): Set<string> {
  try { return new Set(JSON.parse(localStorage.getItem(KEY) ?? '[]')); } catch { return new Set(); }
}

const { subscribe, update } = writable<Set<string>>(load());

export const hidden = {
  subscribe,
  isHidden(id: string): boolean {
    let v = false;
    hidden.subscribe(s => { v = s.has(id); })();
    return v;
  },
  toggle(id: string) {
    update(s => {
      const next = new Set(s);
      next.has(id) ? next.delete(id) : next.add(id);
      localStorage.setItem(KEY, JSON.stringify([...next]));
      return next;
    });
  },
};
