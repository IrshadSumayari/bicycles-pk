import { describe, it, expect } from "vitest";
import {
  returnSubmissionError,
  returnReviewActions,
  evidenceFileError,
  type ReturnSubmission,
} from "../../shared/returns";
const p: ReturnSubmission = {
  order_no: "WEB-1",
  request_id: "test",
  reason: "damaged",
  requested_resolution: "exchange",
  message: "The seam has a visible tear.",
  items: [{ line_no: 1, quantity: 1 }],
};
describe("online return request validation", () => {
  it("accepts only quantities from the delivered order snapshot", () => {
    expect(returnSubmissionError(p, [{ line_no: 1, quantity: 2 }])).toBeNull();
    for (const items of [
      [],
      [{ line_no: 1, quantity: 3 }],
      [{ line_no: 1, quantity: 1.5 }],
      [{ line_no: 2, quantity: 1 }],
      [
        { line_no: 1, quantity: 1 },
        { line_no: 1, quantity: 1 },
      ],
    ])
      expect(
        returnSubmissionError({ ...p, items }, [{ line_no: 1, quantity: 2 }]),
      ).not.toBeNull();
  });
  it("requires review context instead of an automatic refund choice", () => {
    for (const patch of [
      { reason: "bad" },
      { requested_resolution: "automatic" },
      { message: " " },
      { message: "x".repeat(2001) },
    ])
      expect(
        returnSubmissionError({ ...p, ...patch }, [
          { line_no: 1, quantity: 2 },
        ]),
      ).not.toBeNull();
  });
  it("does not allow a submitted request to close or count as received", () => {
    expect(returnReviewActions("submitted")).toEqual([
      "needs_information",
      "return_authorized",
      "rejected",
    ]);
    expect(returnReviewActions("return_authorized")).toEqual([
      "received",
      "closed",
    ]);
    expect(returnReviewActions("closed")).toEqual([]);
    expect(returnReviewActions("rejected")).toEqual([]);
  });
  it("refuses SVGs, empty and oversized uploads", () => {
    expect(evidenceFileError({ type: "image/webp", size: 200 })).toBeNull();
    for (const f of [
      { type: "image/svg+xml", size: 20 },
      { type: "image/jpeg", size: 0 },
      { type: "image/png", size: 10 * 1024 * 1024 + 1 },
    ])
      expect(evidenceFileError(f)).not.toBeNull();
  });
});
