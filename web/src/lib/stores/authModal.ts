import { writable } from 'svelte/store';

// Pending action to execute after successful login.
// Components set this before opening the modal; the modal clears it on success.
export const pendingAuthAction = writable<(() => void) | null>(null);

// Set to true to open the AuthModal from anywhere.
export const showAuthModal = writable(false);

export function requireAuth(action: () => void): void {
  pendingAuthAction.set(action);
  showAuthModal.set(true);
}
