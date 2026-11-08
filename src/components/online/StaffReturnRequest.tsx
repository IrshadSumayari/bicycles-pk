import { useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { returnRequests, type ReturnReview } from "../../lib/returnRequests";
import { getErrorMessage } from "../../lib/errors";
import {
  returnReasons,
  returnStatuses,
  returnReviewActions,
  type ReturnRequest,
  type ReturnStatus,
} from "../../../shared/returns";
import { ReturnPhotos } from "./ReturnPhotos";
export function StaffReturnRequest({
  orderId,
  userId,
}: {
  orderId: string;
  userId: string;
}) {
  const client = useQueryClient();
  const query = useQuery({
    queryKey: ["online-return-request", userId, orderId],
    queryFn: () => returnRequests.detail(orderId),
  });
  async function refresh() {
    await query.refetch();
    await client.invalidateQueries({
      queryKey: ["online-return-requests", userId],
    });
  }
  return (
    <section className="card p-4 space-y-4 lg:col-span-2">
      <h2 className="text-xl font-semibold">Customer return review</h2>
      <p>
        Review only: this workflow does not refund payments, exchange products
        or change stock.
      </p>
      {query.isLoading && <p role="status">Loading request…</p>}
      {query.error && <p role="alert">{getErrorMessage(query.error)}</p>}
      {query.data ? (
        <Review
          key={query.data.id + ":" + query.data.version}
          request={query.data}
          refresh={refresh}
        />
      ) : query.isSuccess ? (
        <p>No customer return request for this order.</p>
      ) : null}
      <button
        className="btn btn-secondary btn-md"
        disabled={query.isFetching}
        onClick={() => void refresh()}
      >
        Refresh return review
      </button>
    </section>
  );
}
function Review({
  request,
  refresh,
}: {
  request: ReturnRequest;
  refresh: () => Promise<void>;
}) {
  const actions = returnReviewActions(request.status);
  const [status, setStatus] = useState<ReturnStatus>(
      actions[0] ?? request.status,
    ),
    [message, setMessage] = useState(""),
    [note, setNote] = useState(request.staff_note ?? ""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const pending = useRef<ReturnReview | null>(null);
  async function submit() {
    if (busy) return;
    setError("");
    if (!message.trim()) {
      setError("Write the update the customer should see.");
      return;
    }
    setBusy(true);
    const p = pending.current ?? {
      id: request.id,
      version: request.version,
      status,
      message,
      staff_note: note,
      request_id: crypto.randomUUID(),
    };
    pending.current = p;
    try {
      await returnRequests.review(p);
      pending.current = null;
      await refresh();
    } catch (e) {
      if (
        e &&
        typeof e === "object" &&
        "code" in e &&
        ["P0001", "42501"].includes(String(e.code))
      )
        pending.current = null;
      setError(getErrorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="space-y-4">
      <p>
        <strong>{returnStatuses[request.status]}</strong> ·{" "}
        {returnReasons[request.reason]} · Customer preference:{" "}
        {request.requested_resolution}
      </p>
      <ul>
        {request.items.map((i) => (
          <li key={i.line_no}>
            {i.description} ·{" "}
            {[i.sku, i.size, i.color].filter(Boolean).join(" · ")} · Qty{" "}
            {i.quantity}
          </li>
        ))}
      </ul>
      <ol className="space-y-3">
        {request.events.map((e, i) => (
          <li key={i} className="border-l-2 pl-3">
            <strong>
              {e.actor === "staff" ? "Staff" : "Customer"} ·{" "}
              {returnStatuses[e.status]}
            </strong>
            <p className="whitespace-pre-wrap break-words">{e.message}</p>
            <time className="text-sm" dateTime={e.created_at}>
              {new Date(e.created_at).toLocaleString("en-PK", {
                timeZone: "Asia/Karachi",
              })}
            </time>
          </li>
        ))}
      </ol>
      <ReturnPhotos photos={request.photos} onView={returnRequests.photo} />
      {actions.length ? (
        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            void submit();
          }}
        >
          <fieldset disabled={busy || !!pending.current} className="space-y-4">
            <label className="block">
              Review decision
              <select
                className="select w-full"
                value={status}
                onChange={(e) => setStatus(e.target.value as ReturnStatus)}
              >
                {actions.map((s) => (
                  <option key={s} value={s}>
                    {returnStatuses[s]}
                  </option>
                ))}
              </select>
            </label>
            {status === "return_authorized" && (
              <p>
                Confirm eligibility and explain where and how to send the item,
                who pays postage, and the agreed next steps. Sending
                instructions does not approve a refund.
              </p>
            )}
            {status === "closed" && (
              <p>
                Explain the outcome and any separately arranged refund or
                exchange. Closing this request does not record a payment or
                stock return.
              </p>
            )}
            <label className="block">
              Customer update (visible to the customer)
              <textarea
                className="input w-full"
                rows={4}
                maxLength={2000}
                required
                value={message}
                onChange={(e) => setMessage(e.target.value)}
              />
            </label>
            <label className="block">
              Internal staff note (not shown to the customer)
              <textarea
                className="input w-full"
                rows={3}
                maxLength={2000}
                value={note}
                onChange={(e) => setNote(e.target.value)}
              />
            </label>
          </fieldset>
          {error && <p role="alert">{error}</p>}
          <button className="btn btn-primary btn-md" disabled={busy}>
            {pending.current
              ? "Retry review update"
              : "Save review & customer update"}
          </button>
        </form>
      ) : (
        <div>
          <p>
            This request is closed. Contact the customer directly for further
            concerns.
          </p>
          {request.staff_note && (
            <p className="whitespace-pre-wrap break-words">
              <strong>Internal note:</strong> {request.staff_note}
            </p>
          )}
        </div>
      )}
    </div>
  );
}
