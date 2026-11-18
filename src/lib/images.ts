export function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80)
    .replace(/-+$/g, '');
}

export function validateImageFile(file: Pick<File, 'type' | 'size'>): void {
  if (!file.type.startsWith('image/')) throw new Error('Choose an image file');
  if (file.size > 10 * 1024 * 1024)
    throw new Error('Choose an image of 10 MB or less');
}

export async function resizeImage(
  file: File,
  maxSide = 1600,
  quality = 0.82,
): Promise<Blob> {
  validateImageFile(file);
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    const scale = Math.min(
      1,
      maxSide / Math.max(image.naturalWidth, image.naturalHeight),
    );
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    const context = canvas.getContext('2d');
    if (!context) throw new Error('This browser cannot resize images');
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    const encode = (type: string) =>
      new Promise<Blob | null>((resolve) =>
        canvas.toBlob(resolve, type, quality),
      );
    const webp = await encode('image/webp');
    if (webp?.type === 'image/webp') return webp;
    const jpeg = await encode('image/jpeg');
    if (!jpeg || jpeg.type !== 'image/jpeg')
      throw new Error('Could not prepare the image. Try another file');
    return jpeg;
  } catch (error) {
    if (error instanceof Error && error.name !== 'EncodingError') throw error;
    throw new Error('Could not read this image. Try a JPEG, PNG or WebP file', {
      cause: error,
    });
  } finally {
    URL.revokeObjectURL(url);
  }
}
