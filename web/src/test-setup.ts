// Mock localStorage for all unit tests
const store: Record<string, string> = {};
const localStorageMock = {
  getItem: (k: string) => store[k] ?? null,
  setItem: (k: string, v: string) => { store[k] = v; },
  removeItem: (k: string) => { delete store[k]; },
  clear: () => { Object.keys(store).forEach(k => delete store[k]); },
  get length() { return Object.keys(store).length; },
  key: (i: number) => Object.keys(store)[i] ?? null,
};
Object.defineProperty(globalThis, 'localStorage', { value: localStorageMock, writable: true });

// Mock Audio element (player store creates it)
class MockAudio {
  src = ''; volume = 1; currentTime = 0;
  pause() {} load() {} play() { return Promise.resolve(); }
  addEventListener() {}
}
Object.defineProperty(globalThis, 'Audio', { value: MockAudio, writable: true });
