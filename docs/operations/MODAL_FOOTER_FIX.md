# Modal footer layout correction

23 October 2026, local POS working tree. No schema or production changes.

Add Style placed its scrollable body and footer inside a form that did not inherit the shell's constrained flex height. The body's fixed viewport subtraction also failed to account for the extra Details/Website tabs, wrapping headers and browser zoom. The shell clipped the resulting footer.

The shared layout now constrains direct-child forms as flex columns with min-height zero, keeps headers/tabs/footers from shrinking, and makes only the body consume and scroll within the remaining space. Removed the fixed body-height subtraction; the shell uses the dynamic viewport with a legacy viewport fallback. Footer buttons wrap with gaps on narrow screens. Long headings wrap and close buttons keep their width.

Audited both shared ModalShell callers and plain elements using the modal classes: style, stock adjustment, fabric rolls, label printing, checkout, returns, receipts, cash shift actions/history, discount/customer editors, customer payments/details/statements, shift details/forced close, transaction details, lookup/garment editors, tailoring conversion and order dialogs. The separate User editor is now on the same header/body/footer structure. The Style Website tab also uses the shared scrollable body. Existing nested forms inside a modal body are unaffected by the direct-child form rule.

Review at 375x667, 768x600, desktop and 200% zoom: open Add Style with many rows, scroll to the last variant, and confirm Cancel/Save remain visible; repeat with checkout, customer/user/lookup forms and tailoring dialogs. Browser automation initialization is currently failing on this machine, so this visual pass has not been completed. Run the production build/typecheck and existing frontend tests for source validation.
