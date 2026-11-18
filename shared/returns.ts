export const returnReasons = {
  damaged: "Damaged or faulty item",
  wrong_item: "Wrong item received",
  size_fit: "Size or fit concern",
  other: "Other issue",
} as const;
export const returnStatuses = {
  submitted: "Awaiting staff review",
  needs_information: "More information needed",
  return_authorized: "Return instructions provided",
  received: "Items received for review",
  closed: "Request closed",
  rejected: "Request declined",
} as const;
export type ReturnStatus = keyof typeof returnStatuses;
export type ReturnPhoto = {
  id: string;
  storage_path: string;
  uploaded: boolean;
};
export type ReturnRequest = {
  id: string;
  order_no: string;
  reason: keyof typeof returnReasons;
  requested_resolution: "refund" | "exchange";
  message: string;
  status: ReturnStatus;
  version: number;
  created_at: string;
  updated_at: string;
  staff_note?: string;
  items: {
    line_no: number;
    description: string;
    sku: string | null;
    size: string | null;
    color: string | null;
    quantity: number;
  }[];
  events: {
    actor: "customer" | "staff";
    status: ReturnStatus;
    message: string;
    created_at: string;
  }[];
  photos: ReturnPhoto[];
};
export type ReturnSubmission = {
  order_no: string;
  request_id: string;
  reason: string;
  requested_resolution: string;
  message: string;
  items: { line_no: number; quantity: number }[];
};
export function returnSubmissionError(
  p: ReturnSubmission,
  lines: { line_no: number; quantity: number }[],
): string | null {
  if (
    !Object.hasOwn(returnReasons, p.reason) ||
    !["refund", "exchange"].includes(p.requested_resolution)
  )
    return "Choose a reason and preferred resolution.";
  if (p.message.trim().length < 10 || p.message.trim().length > 2000)
    return "Describe the issue in 10–2000 characters.";
  if (!p.items.length || p.items.length > 50)
    return "Select the items for this request.";
  const seen = new Set<number>();
  for (const i of p.items) {
    const line = lines.find((l) => l.line_no === i.line_no);
    if (
      !line ||
      seen.has(i.line_no) ||
      !Number.isInteger(i.quantity) ||
      i.quantity < 1 ||
      i.quantity > line.quantity
    )
      return "Choose each item once, within its ordered quantity.";
    seen.add(i.line_no);
  }
  return null;
}
export function returnReviewActions(status: ReturnStatus): ReturnStatus[] {
  switch (status) {
    case "submitted":
    case "needs_information":
      return ["needs_information", "return_authorized", "rejected"];
    case "return_authorized":
      return ["received", "closed"];
    case "received":
      return ["closed"];
    default:
      return [];
  }
}
export function evidenceFileError(file: {
  type: string;
  size: number;
}): string | null {
  if (!["image/jpeg", "image/png", "image/webp"].includes(file.type))
    return "Choose a JPEG, PNG or WebP product photo.";
  if (file.size <= 0 || file.size > 10 * 1024 * 1024)
    return "Choose a photo of 10 MB or less.";
  return null;
}
export async function prepareEvidenceImage(file: File): Promise<Blob> {
  const error = evidenceFileError(file);
  if (error) throw new Error(error);
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    if (
      !image.naturalWidth ||
      !image.naturalHeight ||
      image.naturalWidth * image.naturalHeight > 40_000_000
    )
      throw new Error("Choose a smaller product photo.");
    const scale = Math.min(
      1,
      1600 / Math.max(image.naturalWidth, image.naturalHeight),
    );
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    const context = canvas.getContext("2d");
    if (!context) throw new Error("This browser cannot prepare photos.");
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, "image/webp", 0.82),
    );
    if (!blob || blob.type !== "image/webp" || blob.size > 5 * 1024 * 1024)
      throw new Error(
        "Could not prepare this photo. Try a smaller image or another browser.",
      );
    return blob;
  } finally {
    URL.revokeObjectURL(url);
  }
}
