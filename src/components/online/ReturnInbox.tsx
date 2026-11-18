import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { returnRequests } from "../../lib/returnRequests";
import { returnStatuses } from "../../../shared/returns";
import { getErrorMessage } from "../../lib/errors";
export function ReturnInbox({
  userId,
  onSelect,
}: {
  userId: string;
  onSelect: (id: string) => void;
}) {
  const [status, setStatus] = useState("active"),
    [offset, setOffset] = useState(0);
  const query = useQuery({
    queryKey: ["online-return-requests", userId, status, offset],
    queryFn: () => returnRequests.list(status, offset),
    refetchInterval: 30_000,
  });
  return (
    <section className="space-y-4">
      <h2 className="text-xl font-semibold">Customer return requests</h2>
      <p>
        Review delivered-order concerns here. Courier parcels returned to sender
        are handled on the order separately.
      </p>
      <div className="flex flex-wrap gap-3">
        <label>
          Review status
          <select
            className="select"
            value={status}
            onChange={(e) => {
              setStatus(e.target.value);
              setOffset(0);
            }}
          >
            <option value="active">Active requests</option>
            <option value="all">All requests</option>
            {Object.entries(returnStatuses).map(([v, label]) => (
              <option key={v} value={v}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <button
          className="btn btn-secondary btn-md self-end"
          disabled={query.isFetching}
          onClick={() => void query.refetch()}
        >
          Refresh
        </button>
      </div>
      {query.isLoading && <p role="status">Loading requests…</p>}
      {query.error && <p role="alert">{getErrorMessage(query.error)}</p>}
      <ul className="space-y-3">
        {query.data?.requests.map((r) => (
          <li
            className="card p-4 flex flex-wrap justify-between gap-3"
            key={r.id}
          >
            <div>
              <strong>{r.order_no}</strong>
              <p>{returnStatuses[r.status]}</p>
              <time dateTime={r.updated_at}>
                {new Date(r.updated_at).toLocaleString("en-PK", {
                  timeZone: "Asia/Karachi",
                })}
              </time>
            </div>
            <button
              className="btn btn-primary btn-md"
              onClick={() => onSelect(r.order_id)}
            >
              Review request
            </button>
          </li>
        ))}
      </ul>
      {query.data?.total_count === 0 && <p>No requests match this filter.</p>}
      <div className="flex flex-wrap items-center gap-3">
        <button
          className="btn btn-secondary btn-md"
          disabled={!offset}
          onClick={() => setOffset((n) => Math.max(0, n - 24))}
        >
          Previous
        </button>
        <span>{query.data?.total_count ?? 0} requests</span>
        <button
          className="btn btn-secondary btn-md"
          disabled={offset + 24 >= (query.data?.total_count ?? 0)}
          onClick={() => setOffset((n) => n + 24)}
        >
          Next
        </button>
      </div>
    </section>
  );
}
