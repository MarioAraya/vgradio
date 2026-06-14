import { describe, it, expect } from 'vitest';
import { fmtTime, timeAgo, slugToTitle, letterGradient } from './utils';

describe('fmtTime', () => {
  it('formats zero', () => expect(fmtTime(0)).toBe('0:00'));
  it('formats seconds only', () => expect(fmtTime(45)).toBe('0:45'));
  it('formats minutes and seconds', () => expect(fmtTime(125)).toBe('2:05'));
  it('pads single-digit seconds', () => expect(fmtTime(61)).toBe('1:01'));
  it('handles large values', () => expect(fmtTime(3661)).toBe('61:01'));
  it('handles NaN', () => expect(fmtTime(NaN)).toBe('0:00'));
  it('handles negative', () => expect(fmtTime(-5)).toBe('0:00'));
  it('truncates fractional seconds', () => expect(fmtTime(90.9)).toBe('1:30'));
});

describe('timeAgo', () => {
  it('returns "ahora" for recent time', () => {
    const iso = new Date(Date.now() - 10_000).toISOString();
    expect(timeAgo(iso)).toBe('ahora');
  });
  it('returns minutes for older', () => {
    const iso = new Date(Date.now() - 5 * 60_000).toISOString();
    expect(timeAgo(iso)).toBe('hace 5 min');
  });
  it('returns hours for even older', () => {
    const iso = new Date(Date.now() - 3 * 3_600_000).toISOString();
    expect(timeAgo(iso)).toBe('hace 3 h');
  });
  it('returns days for ancient', () => {
    const iso = new Date(Date.now() - 2 * 86_400_000).toISOString();
    expect(timeAgo(iso)).toBe('hace 2 d');
  });
});

describe('slugToTitle', () => {
  it('converts slug to title case', () => {
    expect(slugToTitle('https://example.com/game-soundtracks/album/super-mario-world'))
      .toBe('Super Mario World');
  });
  it('handles single word', () => {
    expect(slugToTitle('mario')).toBe('Mario');
  });
});

describe('letterGradient', () => {
  it('returns a CSS gradient string', () => {
    const g = letterGradient('Test');
    expect(g).toMatch(/^linear-gradient/);
    expect(g).toContain('hsl(');
  });
  it('returns consistent output for same title', () => {
    expect(letterGradient('Zelda')).toBe(letterGradient('Zelda'));
  });
  it('returns different output for different titles', () => {
    expect(letterGradient('Zelda')).not.toBe(letterGradient('Mario'));
  });
});
