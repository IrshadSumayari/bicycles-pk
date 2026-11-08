"use client";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import type { WebOrder } from "@/lib/orders";
import { customerReturns } from "@/lib/returns";
import { getErrorMessage } from "@/lib/errors";
import {
  returnReasons,
  returnStatuses,
  returnSubmissionError,
  type ReturnRequest,
  type ReturnSubmission,
} from "../../shared/returns";
import { ReturnPhotos } from "./return-photos";
import { Button } from "./ui/button";
export function CustomerReturnRequest({ order }: { order: WebOrder }) {
  const [request, setRequest] = useState<ReturnRequest | null>(null),
    [ready, setReady] = useState(false),
    [loading, setLoading] = useState(true),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [reason, setReason] = useState(""),
    [resolution, setResolution] = useState(""),
    [message, setMessage] = useState(""),
    [reply, setReply] = useState(""),
    [quantities, setQuantities] = useState<Record<number, string>>({});
  const [createFrozen, setCreateFrozen] = useState(false),
    [replyFrozen, setReplyFrozen] = useState(false);
  const pending = useRef<ReturnSubmission | null>(null),
    replyPending = useRef<{
      id: string;
      version: number;
      message: string;
      request_id: string;
    } | null>(null);
  async function refresh() {
    setLoading(true);
    setError("");
    try {
      setRequest(await customerReturns.get(order.order_no));
      setReady(true);
      setCreateFrozen(false);
      setReplyFrozen(false);
      pending.current = null;
      replyPending.current = null;
    } catch (e) {
      setError(getErrorMessage(e));
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    let live = true;
    customerReturns
      .get(order.order_no)
      .then((r) => {
        if (live) {
          setRequest(r);
          setReady(true);
          setLoading(false);
        }
      })
      .catch((e) => {
        if (live) {
          setError(getErrorMessage(e));
          setLoading(false);
        }
      });
    return () => {
      live = false;
    };
  }, [order.order_no]);
  async function submit() {
    if (busy) return;
    setError("");
    const p = pending.current ?? {
      order_no: order.order_no,
      request_id: crypto.randomUUID(),
      reason,
      requested_resolution: resolution,
      message,
      items: Object.entries(quantities)
        .filter(([, q]) => Number(q) > 0)
        .map(([line_no, q]) => ({
          line_no: Number(line_no),
          quantity: Number(q),
        })),
    };
    const issue = returnSubmissionError(p, order.lines);
    if (issue) {
      setError(issue);
      return;
    }
    pending.current = p;
    setBusy(true);
    try {
      setRequest(await customerReturns.create(p));
      pending.current = null;
    } catch (e) {
      if (
        e &&
        typeof e === "object" &&
        "code" in e &&
        ["P0001", "42501", "22P02"].includes(String(e.code))
      )
        pending.current = null;
      setError(getErrorMessage(e));
    } finally {
      setBusy(false);
      setCreateFrozen(!!pending.current);
      setReplyFrozen(!!replyPending.current);
    }
  }
  async function sendReply() {
    if (!request || busy) return;
    setError("");
    if (!reply.trim() || reply.trim().length > 2000) {
      setError("Enter a reply of 1–2000 characters.");
      return;
    }
    const p = replyPending.current ?? {
      id: request.id,
      version: request.version,
      message: reply,
      request_id: crypto.randomUUID(),
    };
    replyPending.current = p;
    setBusy(true);
    try {
      setRequest(await customerReturns.reply(p));
      replyPending.current = null;
      setReply("");
    } catch (e) {
      if (
        e &&
        typeof e === "object" &&
        "code" in e &&
        ["P0001", "42501"].includes(String(e.code))
      )
        replyPending.current = null;
      setError(getErrorMessage(e));
    } finally {
      setBusy(false);
      setCreateFrozen(!!pending.current);
      setReplyFrozen(!!replyPending.current);
    }
  }
  return (
    <section
      className="lv-order-panel lv-return-request"
      aria-labelledby="return-request-title"
    >
      <h2 id="return-request-title">Returns & exchanges</h2>
      <p>
        Every request is reviewed by staff. A request does not confirm
        eligibility, an exchange or a refund. Please wait for instructions
        before sending a parcel.
      </p>
      {loading ? (
        <p role="status">Loading return request…</p>
      ) : request ? (
        <>
          <p className="lv-return-status">
            <strong>{returnStatuses[request.status]}</strong> · Preferred
            resolution: {request.requested_resolution}
          </p>
          <p>{returnReasons[request.reason]}</p>
          <ul>
            {request.items.map((i) => (
              <li key={i.line_no}>
                {i.description} ·{" "}
                {[i.size, i.color].filter(Boolean).join(" · ")} · Qty{" "}
                {i.quantity}
              </li>
            ))}
          </ul>
          <ol className="lv-return-timeline">
            {request.events.map((e, i) => (
              <li key={i}>
                <strong>
                  {e.actor === "staff" ? "Bicycles.pk" : "You"} ·{" "}
                  {returnStatuses[e.status]}
                </strong>
                <p className="whitespace-pre-line">{e.message}</p>
                <time dateTime={e.created_at}>
                  {new Date(e.created_at).toLocaleString("en-PK", {
                    timeZone: "Asia/Karachi",
                  })}
                </time>
              </li>
            ))}
          </ol>
          <ReturnPhotos
            photos={request.photos}
            onView={customerReturns.photo}
            onUpload={
              ["submitted", "needs_information"].includes(request.status)
                ? async (file, id) => {
                    try {
                      await customerReturns.upload(request.id, file, id);
                    } finally {
                      setRequest(await customerReturns.get(order.order_no));
                    }
                  }
                : undefined
            }
          />
          {request.status === "needs_information" && (
            <form
              onSubmit={(e) => {
                e.preventDefault();
                void sendReply();
              }}
            >
              <label>
                Your reply
                <textarea
                  className="field"
                  rows={3}
                  maxLength={2000}
                  value={reply}
                  disabled={busy || replyFrozen}
                  onChange={(e) => setReply(e.target.value)}
                />
              </label>
              <Button disabled={busy}>
                {replyFrozen ? "Retry reply" : "Send reply"}
              </Button>
            </form>
          )}
          {["closed", "rejected"].includes(request.status) && (
            <p>
              For a further concern about this order,{" "}
              <Link href="/pages/contact">contact us</Link> with your order
              number.
            </p>
          )}
        </>
      ) : order.status === "delivered" && ready ? (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            void submit();
          }}
        >
          <fieldset disabled={busy || createFrozen} className="space-y-4">
            <legend>Request a staff review</legend>
            <p>
              Select all affected items. One request is recorded per order; you
              can add information when staff ask for it.
            </p>
            {order.lines.map((line) => (
              <label className="lv-return-item" key={line.line_no}>
                <span>
                  {line.description} ·{" "}
                  {[line.size, line.color].filter(Boolean).join(" · ")}
                  <small>Ordered: {line.quantity}</small>
                </span>
                <select
                  className="field"
                  aria-label={"Return quantity for " + line.description}
                  value={quantities[line.line_no] ?? "0"}
                  onChange={(e) =>
                    setQuantities({
                      ...quantities,
                      [line.line_no]: e.target.value,
                    })
                  }
                >
                  <option value="0">Not selected</option>
                  {Array.from({ length: line.quantity }, (_, i) => (
                    <option key={i + 1} value={i + 1}>
                      Qty {i + 1}
                    </option>
                  ))}
                </select>
              </label>
            ))}
            <label>
              Reason
              <select
                className="field"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
              >
                <option value="">Choose a reason</option>
                {Object.entries(returnReasons).map(([v, label]) => (
                  <option key={v} value={v}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Preferred resolution
              <select
                className="field"
                value={resolution}
                onChange={(e) => setResolution(e.target.value)}
              >
                <option value="">Choose a preference</option>
                <option value="exchange">Exchange</option>
                <option value="refund">Refund</option>
              </select>
            </label>
            <label>
              Describe the issue
              <textarea
                className="field"
                rows={4}
                maxLength={2000}
                value={message}
                onChange={(e) => setMessage(e.target.value)}
              />
            </label>
            <p>
              Do not include card, bank-account or other sensitive payment
              information. Optional product photos can be added after
              submission.
            </p>
          </fieldset>
          <Button disabled={busy}>
            {createFrozen ? "Retry request" : "Submit for review"}
          </Button>
        </form>
      ) : !error ? (
        <p>
          Return requests become available after delivery.{" "}
          <Link href="/pages/contact">Contact us</Link> for help with your
          order.
        </p>
      ) : null}
      {error && <p role="alert">{error}</p>}
      <div className="flex flex-wrap gap-4">
        <Button
          variant="outline"
          disabled={busy || loading}
          onClick={() => void refresh()}
        >
          Refresh request
        </Button>
        <Link href="/policies/refund-policy">How return reviews work</Link>
      </div>
    </section>
  );
}
