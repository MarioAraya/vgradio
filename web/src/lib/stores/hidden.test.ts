import { describe, it, expect, beforeEach, vi } from 'vitest';
import { get } from 'svelte/store';

beforeEach(() => {
  localStorage.clear();
  vi.resetModules();
});

async function fresh() {
  return import('./hidden');
}

describe('hidden store', () => {
  it('starts empty', async () => {
    const { hidden } = await fresh();
    expect(get(hidden).size).toBe(0);
  });

  it('toggle adds an id', async () => {
    const { hidden } = await fresh();
    hidden.toggle('track-1');
    expect(get(hidden).has('track-1')).toBe(true);
  });

  it('toggle removes an existing id', async () => {
    const { hidden } = await fresh();
    hidden.toggle('track-1');
    hidden.toggle('track-1');
    expect(get(hidden).has('track-1')).toBe(false);
  });

  it('isHidden returns correct value', async () => {
    const { hidden } = await fresh();
    expect(hidden.isHidden('track-1')).toBe(false);
    hidden.toggle('track-1');
    expect(hidden.isHidden('track-1')).toBe(true);
  });

  it('persists to localStorage', async () => {
    const { hidden } = await fresh();
    hidden.toggle('track-x');
    const raw = JSON.parse(localStorage.getItem('vgradio.hiddenTracks') ?? '[]');
    expect(raw).toContain('track-x');
  });
});
