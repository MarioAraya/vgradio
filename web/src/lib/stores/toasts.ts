import { writable } from 'svelte/store';

export interface Toast {
  id: number;
  message: string;
  type: 'error' | 'info';
}

const { subscribe, update } = writable<Toast[]>([]);
let _id = 0;

export const toasts = { subscribe };

export function addToast(message: string, type: Toast['type'] = 'info', durationMs = 3500) {
  const id = ++_id;
  update(ts => [...ts, { id, message, type }]);
  setTimeout(() => {
    update(ts => ts.filter(t => t.id !== id));
  }, durationMs);
}
