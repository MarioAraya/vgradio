import { describe, it, expect, beforeEach } from 'vitest';

beforeEach(() => localStorage.clear());

async function freshApi() {
  return import('./api?t=' + Date.now());
}

describe('api.coverURL', () => {
  it('returns external URLs unchanged', async () => {
    const { api } = await freshApi();
    const url = 'https://cdn.example.com/cover.jpg';
    expect(api.coverURL(url)).toBe(url);
  });

  it('prepends backend base for relative paths', async () => {
    const { api } = await freshApi();
    expect(api.coverURL('/covers/abc/cover_0.jpg'))
      .toMatch(/^http:\/\/.+:8080\/covers\/abc\/cover_0\.jpg$/);
  });
});

describe('api.streamURL / downloadURL', () => {
  it('prepends base URL to streamUrl', async () => {
    const { api } = await freshApi();
    const track = {
      id: 't1', name: 'Track', index: 0, durationSec: 60,
      sizeBytes: 0, streamUrl: '/tracks/t1/stream',
      downloadUrl: '/tracks/t1/download', downloaded: false,
    };
    expect(api.streamURL(track)).toContain('/tracks/t1/stream');
    expect(api.downloadURL(track)).toContain('/tracks/t1/download');
  });
});

describe('origURL regex', () => {
  // Extracted logic from CoverLightbox — tests the naming convention
  function origURL(url: string): string {
    return url.replace(/(cover_\d+)(\.[^.]+)$/, '$1_orig$2');
  }

  it('inserts _orig before extension for JPEG', () => {
    expect(origURL('/covers/abc/cover_0.jpg')).toBe('/covers/abc/cover_0_orig.jpg');
  });
  it('inserts _orig for PNG', () => {
    expect(origURL('/covers/abc/cover_3.png')).toBe('/covers/abc/cover_3_orig.png');
  });
  it('handles higher indices', () => {
    expect(origURL('/covers/abc/cover_12.jpg')).toBe('/covers/abc/cover_12_orig.jpg');
  });
  it('is idempotent on already-orig URLs', () => {
    // The regex only matches cover_N (digits), so cover_0_orig won't re-match
    const orig = origURL('/covers/abc/cover_0.jpg');
    expect(origURL(orig)).toBe(orig);
  });
});
