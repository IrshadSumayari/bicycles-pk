export const PLATFORM_NAME = 'Bicycles POS';
// Shown wherever no store logo has been uploaded in Settings.
export const PLATFORM_LOGO = '/bicycles-icon.svg';

// Compatibility with installations created before the Bicycles.pk rebrand.
export function platformStoreName(value: string | null | undefined): string {
  return !value?.trim() || /nextera/i.test(value) ? PLATFORM_NAME : value;
}

export function platformReceiptText(value: string | null | undefined): string {
  return (value ?? '').replace(/nextera(?:\s+pos)?(?:\s+(?:store|system))?/gi, PLATFORM_NAME);
}

export function platformStoreEmail(value: string | null | undefined): string {
  return /nextera/i.test(value ?? '') ? '' : (value ?? '');
}
