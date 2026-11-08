import { afterEach, describe, expect, it, vi } from 'vitest';
const { ping } = vi.hoisted(() => ({
  ping: vi.fn<(signal: AbortSignal) => Promise<void>>(),
}));
vi.mock('./services', () => ({ settingsService: { ping } }));
import {
  connectionStore,
  isNetworkError,
  nextState,
  type ConnectionState,
} from './connection';

const base: ConnectionState = {
  status: 'online',
  browserOnline: true,
  lastSuccessfulCheck: null,
};
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  ping.mockReset();
});

describe('connection transitions', () => {
  it('moves online → slow → offline → online and records successful checks', () => {
    const slow = nextState(base, { type: 'success', elapsed: 2001, at: 100 });
    expect(slow.status).toBe('slow');
    const offline = nextState(slow, { type: 'failure' });
    expect(offline).toEqual({
      ...base,
      status: 'offline',
      lastSuccessfulCheck: 100,
    });
    expect(
      nextState(offline, { type: 'success', elapsed: 500, at: 200 }),
    ).toEqual({ ...base, lastSuccessfulCheck: 200 });
  });
  it('handles repeated failures, browser recovery and the exact slow threshold', () => {
    const offline = nextState(nextState(base, { type: 'failure' }), {
      type: 'failure',
    });
    expect(offline.status).toBe('offline');
    const down = nextState(base, { type: 'browser', online: false });
    expect(nextState(down, { type: 'success', elapsed: 1, at: 100 })).toBe(
      down,
    );
    const restored = nextState(down, { type: 'browser', online: true });
    expect(restored.status).toBe('offline');
    expect(
      nextState(restored, { type: 'success', elapsed: 2000, at: 200 }).status,
    ).toBe('online');
  });
  it('polls only with subscribers, times out and checks immediately on reconnection', async () => {
    vi.useFakeTimers();
    const browser = new EventTarget();
    const navigatorState = { onLine: true };
    vi.stubGlobal('window', browser);
    vi.stubGlobal('navigator', navigatorState);
    ping.mockResolvedValue();
    const stop = connectionStore.subscribe(vi.fn());
    const stopSecond = connectionStore.subscribe(vi.fn());
    try {
      await vi.advanceTimersByTimeAsync(0);
      expect(ping).toHaveBeenCalledTimes(1);
      stopSecond();
      ping.mockImplementation(() => new Promise(() => {}));
      await vi.advanceTimersByTimeAsync(30_000);
      const signal = ping.mock.calls.at(-1)![0];
      await vi.advanceTimersByTimeAsync(5000);
      expect(signal.aborted).toBe(true);
      expect(connectionStore.getSnapshot().status).toBe('offline');
      navigatorState.onLine = false;
      browser.dispatchEvent(new Event('offline'));
      ping.mockResolvedValue();
      navigatorState.onLine = true;
      browser.dispatchEvent(new Event('online'));
      await vi.advanceTimersByTimeAsync(0);
      expect(connectionStore.getSnapshot().status).toBe('online');
    } finally {
      stop();
    }
    expect(vi.getTimerCount()).toBe(0);
    const calls = ping.mock.calls.length;
    await vi.advanceTimersByTimeAsync(60_000);
    expect(ping).toHaveBeenCalledTimes(calls);
  });
  it('distinguishes network errors from server validation errors', () => {
    expect(isNetworkError(new TypeError('Failed to fetch'))).toBe(true);
    expect(
      isNetworkError({ message: 'TypeError: Failed to fetch', code: '' }),
    ).toBe(true);
    expect(isNetworkError({ message: 'Out of stock', code: 'P0001' })).toBe(
      false,
    );
    expect(isNetworkError(new Error('Choose a card type'))).toBe(false);
  });
});
