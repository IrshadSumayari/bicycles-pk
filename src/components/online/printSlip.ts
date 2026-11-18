// Print just the slip in a new window
export function printSlip() {
  const slip = document.querySelector('.order-slip');
  if (!slip) return;
  const win = window.open('', '_blank', 'width=420,height=700');
  if (!win) return;
  const style = win.document.createElement('style');
  style.textContent = `
    body { font-family: Arial, Helvetica, sans-serif; font-size: 12px; margin: 8mm; width: 72mm; }
    table { width: 100%; border-collapse: collapse; } td { padding: 2px 0; vertical-align: top; }
    .text-right { text-align: right; } .text-center { text-align: center; } .font-bold, .font-semibold { font-weight: bold; }
    .flex { display: flex; justify-content: space-between; } .text-xs { font-size: 10px; } .text-lg { font-size: 15px; }
    .border-t { border-top: 1px solid #999; } p { margin: 2px 0; }`;
  win.document.head.appendChild(style);
  win.document.body.innerHTML = slip.outerHTML;
  win.setTimeout(() => { win.print(); win.close(); }, 200);
}
