import { describe, it, expect, beforeEach, vi } from 'vitest';
import { get } from 'svelte/store';

beforeEach(() => {
  vi.useRealTimers();
  vi.resetModules();
});

describe('toasts store', () => {
  it('addToast adds a toast', async () => {
    vi.useFakeTimers();
    const { toasts, addToast } = await import('./toasts');
    addToast('Hello', 'info');
    expect(get(toasts)).toHaveLength(1);
    expect(get(toasts)[0].message).toBe('Hello');
    expect(get(toasts)[0].type).toBe('info');
  });

  it('toast auto-dismisses after duration', async () => {
    vi.useFakeTimers();
    const { toasts, addToast } = await import('./toasts');
    addToast('Gone soon', 'error', 1000);
    expect(get(toasts)).toHaveLength(1);
    vi.advanceTimersByTime(1001);
    expect(get(toasts)).toHaveLength(0);
  });

  it('multiple toasts are independent', async () => {
    vi.useFakeTimers();
    const { toasts, addToast } = await import('./toasts');
    addToast('First', 'info', 500);
    addToast('Second', 'error', 2000);
    vi.advanceTimersByTime(600);
    expect(get(toasts)).toHaveLength(1);
    expect(get(toasts)[0].message).toBe('Second');
  });

  it('each toast gets a unique id', async () => {
    vi.useFakeTimers();
    const { toasts, addToast } = await import('./toasts');
    addToast('A', 'info');
    addToast('B', 'info');
    const ids = get(toasts).map(t => t.id);
    expect(new Set(ids).size).toBe(2);
  });
});
