import { writable } from 'svelte/store';
import { browser } from '$app/environment';

export type Theme = 'dark' | 'light' | 'auto';

const KEY = 'vgradio.theme';

function read(): Theme {
  if (!browser) return 'dark';
  const v = localStorage.getItem(KEY);
  return v === 'light' || v === 'auto' ? v : 'dark';
}

function apply(t: Theme) {
  if (browser) document.documentElement.dataset.theme = t;
}

export const theme = writable<Theme>(read());

export function setTheme(t: Theme) {
  if (browser) localStorage.setItem(KEY, t);
  apply(t);
  theme.set(t);
}

// The inline script in app.html already set data-theme before first paint;
// this keeps it in sync if the store is initialized later (e.g. after hydration).
if (browser) apply(read());
