export function customerStatementLink(
  phone: string | null,
  name: string,
  store: string,
  from: string,
  to: string,
  balance: number,
  currency: string,
): string | null {
  if (!phone) return null;
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 10) return null;
  const message = `Assalam o Alaikum ${name},\nYour statement at ${store} for ${from} to ${to}: closing balance ${currency} ${balance.toFixed(2)}.\nPlease contact us for the full statement. Thank you!`;
  return `https://wa.me/${digits}?text=${encodeURIComponent(message)}`;
}

// Clone only the requested document, keeping user text out of HTML strings.
export function printAccountDocument(content: HTMLElement | null): void {
  if (!content) return;
  const popup = window.open('', '_blank', 'width=850,height=700');
  if (!popup) throw new Error('Allow pop-ups to print this document');
  popup.document.title = 'Customer account';
  const style = popup.document.createElement('style');
  style.textContent =
    'body{font:14px sans-serif;margin:24px;color:#111}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:8px;border-bottom:1px solid #ddd}p{white-space:pre-wrap}h2{font-size:22px}';
  popup.document.head.appendChild(style);
  popup.document.body.appendChild(content.cloneNode(true));
  popup.document.close();
  popup.focus();
  popup.setTimeout(() => {
    popup.print();
    popup.close();
  }, 250);
}
