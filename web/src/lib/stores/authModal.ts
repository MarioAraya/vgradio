import { writable, get } from 'svelte/store';
import { currentUser } from './auth';

// Pending action to execute after successful login.
// Components set this before opening the modal; the modal clears it on success.
export const pendingAuthAction = writable<(() => void) | null>(null);

// Set to true to open the AuthModal from anywhere.
export const showAuthModal = writable(false);

export function requireAuth(action: () => void): void {
  if (get(currentUser)) {
    action();
    return;
  }
  pendingAuthAction.set(action);
  showAuthModal.set(true);
}
