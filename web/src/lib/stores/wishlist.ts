import { writable } from 'svelte/store';
import type { WishlistItem } from '$lib/types';

const KEY = 'vgradio.wishlist';

const DEFAULTS = [
  'https://downloads.khinsider.com/game-soundtracks/album/super-mario-world-snes-gamerip',
  'https://downloads.khinsider.com/game-soundtracks/album/minecraft',
  'https://downloads.khinsider.com/game-soundtracks/album/persona-3-original-soundtrack',
  'https://downloads.khinsider.com/game-soundtracks/album/castlevania-symphony-of-the-night',
  'https://downloads.khinsider.com/game-soundtracks/album/super-mario-galaxy-ost-super-mario-35th-anniversary-release',
  'https://downloads.khinsider.com/game-soundtracks/album/hotline-miami',
  'https://downloads.khinsider.com/game-soundtracks/album/god-of-war-original-soundtrack',
  'https://downloads.khinsider.com/game-soundtracks/album/super-smash-bros-brawl-gamerip',
  'https://downloads.khinsider.com/game-soundtracks/album/mega-man-x-snes-gamerip',
  'https://downloads.khinsider.com/game-soundtracks/album/donkey-kong-country-snes',
];

function load(): WishlistItem[] {
  try {
    const saved: WishlistItem[] = JSON.parse(localStorage.getItem(KEY) ?? '[]');
    const existing = new Set(saved.map(i => i.url));
    const merged = [...saved, ...DEFAULTS.filter(u => !existing.has(u)).map(u => ({ url: u }))];
    localStorage.setItem(KEY, JSON.stringify(merged));
    return merged;
  } catch { return DEFAULTS.map(url => ({ url })); }
}

const { subscribe, update } = writable<WishlistItem[]>(load());

export const wishlist = {
  subscribe,
  add(url: string) {
    const u = url.trim();
    if (!u) return;
    update(items => {
      if (items.some(i => i.url === u)) return items;
      const next = [...items, { url: u }];
      localStorage.setItem(KEY, JSON.stringify(next));
      return next;
    });
  },
  remove(url: string) {
    update(items => {
      const next = items.filter(i => i.url !== url);
      localStorage.setItem(KEY, JSON.stringify(next));
      return next;
    });
  },
};
