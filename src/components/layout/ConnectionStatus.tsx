import { useSyncExternalStore } from "react";
import { connectionStore } from "../../lib/connection";

export function ConnectionStatus() {
  const connection = useSyncExternalStore(
    connectionStore.subscribe,
    connectionStore.getSnapshot,
    connectionStore.getServerSnapshot,
  );
  const label =
    connection.status === "offline"
      ? "Offline — use the paper sales book"
      : connection.status === "slow"
        ? "Slow connection"
        : "Online";
  return (
    <div
      role="status"
      aria-live="polite"
      className={`flex items-center gap-2 text-xs ${connection.status === "offline" ? "text-error" : connection.status === "slow" ? "text-warning" : "text-success"}`}
      title={
        connection.lastSuccessfulCheck
          ? `Last successful check: ${new Date(connection.lastSuccessfulCheck).toLocaleTimeString()}`
          : "No successful connection check yet"
      }
    >
      <span
        aria-hidden="true"
        className={`h-2 w-2 shrink-0 rounded-full ${connection.status === "offline" ? "bg-error" : connection.status === "slow" ? "bg-warning" : "bg-success"}`}
      />
      <span className={connection.status === "online" ? "sr-only" : "max-w-44"}>
        {label}
      </span>
    </div>
  );
}
