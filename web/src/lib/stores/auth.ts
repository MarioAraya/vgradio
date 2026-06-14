import { writable } from 'svelte/store';
import type { User } from '$lib/types';

export const currentUser = writable<User | null>(null);
// true while the initial /auth/me request is in flight
export const authLoading = writable(true);

// Fetches the current session from the backend and hydrates the store.
// Call once at app startup (in layout).
export async function initAuth(baseURL: string): Promise<void> {
  try {
    const r = await fetch(baseURL + '/auth/me', { credentials: 'include' });
    if (r.ok) {
      const data = await r.json();
      currentUser.set(data ?? null);
    } else {
      currentUser.set(null);
    }
  } catch {
    currentUser.set(null);
  } finally {
    authLoading.set(false);
  }
}

export async function logout(baseURL: string): Promise<void> {
  await fetch(baseURL + '/auth/logout', { method: 'POST', credentials: 'include' });
  currentUser.set(null);
}
