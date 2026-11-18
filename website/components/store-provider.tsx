"use client";
import {
  createContext,
  useContext,
  useState,
  useSyncExternalStore,
} from "react";
import dynamic from "next/dynamic";
import {
  CART_KEY,
  CART_VERSION,
  cartReducer,
  readCart,
  type CartAction,
  type CartLine,
} from "@/lib/cart";

const CartDrawer = dynamic(() =>
  import("./cart").then((module) => module.CartDrawer),
);
type Store = {
  lines: CartLine[];
  ready: boolean;
  dispatch: (action: CartAction) => void;
  open: () => void;
  cartOpen: boolean;
  setCartOpen: (open: boolean) => void;
};
const Context = createContext<Store | null>(null);
const EMPTY: CartLine[] = [];
let cached = EMPTY;
let cachedRaw: string | null | undefined;
const listeners = new Set<() => void>();
function snapshot() {
  try {
    const raw = localStorage.getItem(CART_KEY);
    if (raw !== cachedRaw) {
      cached = readCart(raw);
      cachedRaw = raw;
    }
  } catch {
    /* Preserve in-memory intent. */
  }
  return cached;
}
function subscribe(listener: () => void) {
  listeners.add(listener);
  const sync = (event: StorageEvent) => {
    if (event.key === CART_KEY || event.key === null) listener();
  };
  window.addEventListener("storage", sync);
  return () => {
    listeners.delete(listener);
    window.removeEventListener("storage", sync);
  };
}
function dispatch(action: CartAction) {
  cached = cartReducer(snapshot(), action);
  const raw = JSON.stringify({ version: CART_VERSION, lines: cached });
  try {
    localStorage.setItem(CART_KEY, raw);
    cachedRaw = raw;
  } catch {
    /* In-memory bag still works. */
  }
  listeners.forEach((listener) => listener());
}
const serverSnapshot = () => null;
export function StoreProvider({ children }: { children: React.ReactNode }) {
  const stored = useSyncExternalStore(subscribe, snapshot, serverSnapshot);
  const [cartOpen, setCartOpen] = useState(false),
    [opened, setOpened] = useState(false);
  const open = () => {
    setOpened(true);
    setCartOpen(true);
  };
  return (
    <Context.Provider
      value={{
        lines: stored ?? EMPTY,
        ready: stored !== null,
        dispatch,
        open,
        cartOpen,
        setCartOpen,
      }}
    >
      {children}
      {opened && <CartDrawer />}
    </Context.Provider>
  );
}
export function useStore() {
  const store = useContext(Context);
  if (!store) throw new Error("StoreProvider missing");
  return store;
}
