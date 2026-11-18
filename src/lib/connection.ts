import { settingsService } from './services';
import { getErrorMessage } from './errors';

export type ConnectionState = {
  status: 'online' | 'slow' | 'offline';
  browserOnline: boolean;
  lastSuccessfulCheck: number | null;
};
export type ConnectionEvent =
  | { type: 'browser'; online: boolean }
  | { type: 'success'; elapsed: number; at: number }
  | { type: 'failure' };

export function nextState(
  previous: ConnectionState,
  event: ConnectionEvent,
): ConnectionState {
  if (event.type === 'browser') {
    return {
      ...previous,
      browserOnline: event.online,
      status: event.online ? previous.status : 'offline',
    };
  }
  if (event.type === 'failure') return { ...previous, status: 'offline' };
  if (!previous.browserOnline) return previous;
  return {
    ...previous,
    status: event.elapsed > 2000 ? 'slow' : 'online',
    lastSuccessfulCheck: event.at,
  };
}

export function isNetworkError(error: unknown): boolean {
  if (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code
  ) {
    return /^(ECONNRESET|ECONNREFUSED|ETIMEDOUT|PGRST00[0-3])$/.test(
      String(error.code),
    );
  }
  return (
    /failed to fetch|fetch failed|network\s?(error|request failed)|load failed|connection (lost|reset|refused)|timed?\s?out|aborterror/i.test(
      getErrorMessage(error),
    ) ||
    (error instanceof DOMException && error.name === 'AbortError')
  );
}

const serverState: ConnectionState = {
  status: 'online',
  browserOnline: true,
  lastSuccessfulCheck: null,
};
let state: ConnectionState = { ...serverState };
const listeners = new Set<() => void>();
let timer: ReturnType<typeof setInterval> | undefined;
let controller: AbortController | undefined;
let requestTimeout: ReturnType<typeof setTimeout> | undefined;
let generation = 0;

function publish(event: ConnectionEvent) {
  state = nextState(state, event);
  listeners.forEach((listener) => listener());
}

async function check() {
  if (!navigator.onLine) {
    offline();
    return;
  }
  controller?.abort();
  clearTimeout(requestTimeout);
  const current = ++generation;
  const request = new AbortController();
  controller = request;
  const started = performance.now();
  const timeout = setTimeout(() => {
    request.abort();
    if (current === generation && listeners.size) publish({ type: 'failure' });
  }, 5000);
  requestTimeout = timeout;
  try {
    await settingsService.ping(request.signal);
    if (current === generation && listeners.size && !request.signal.aborted)
      publish({
        type: 'success',
        elapsed: performance.now() - started,
        at: Date.now(),
      });
  } catch {
    if (current === generation && listeners.size) publish({ type: 'failure' });
  } finally {
    clearTimeout(timeout);
    if (current === generation) controller = undefined;
  }
}

function offline() {
  ++generation;
  controller?.abort();
  controller = undefined;
  clearTimeout(requestTimeout);
  publish({ type: 'browser', online: false });
}
function online() {
  publish({ type: 'browser', online: true });
  void check();
}

export const connectionStore = {
  getSnapshot: () => state,
  getServerSnapshot: () => serverState,
  subscribe(listener: () => void) {
    listeners.add(listener);
    if (listeners.size === 1 && typeof window !== 'undefined') {
      window.addEventListener('online', online);
      window.addEventListener('offline', offline);
      publish({ type: 'browser', online: navigator.onLine });
      void check();
      timer = setInterval(() => void check(), 30_000);
    }
    return () => {
      listeners.delete(listener);
      if (!listeners.size && typeof window !== 'undefined') {
        clearInterval(timer);
        timer = undefined;
        ++generation;
        controller?.abort();
        controller = undefined;
        clearTimeout(requestTimeout);
        window.removeEventListener('online', online);
        window.removeEventListener('offline', offline);
      }
    };
  },
};
