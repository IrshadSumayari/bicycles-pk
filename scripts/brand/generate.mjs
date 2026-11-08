import sharp from "sharp";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const source =
  process.argv[2] ??
  path.join(root, "website/public/brand/ladyvogue-logo-source.png");
const out = path.join(root, "website/public/brand");
const { data, info } = await sharp(source)
  .removeAlpha()
  .raw()
  .toBuffer({ resolveWithObject: true });
const histogram = new Map();
for (let i = 0; i < data.length; i += 3) {
  const [r, g, b] = data.subarray(i, i + 3);
  if (r < 225 && g < 225 && b < 180 && r - b > 20 && g - b > 15) {
    const key = `${r},${g},${b}`;
    histogram.set(key, (histogram.get(key) ?? 0) + 1);
  }
}
const gold = [...histogram]
  .sort((a, b) => b[1] - a[1])[0]?.[0]
  .split(",")
  .map(Number);
if (!gold) throw Error("No gold foreground found");
const rgb = Buffer.alloc(info.width * info.height * 4);
let left = info.width,
  top = info.height,
  right = 0,
  bottom = 0;
for (let y = 0; y < info.height; y++)
  for (let x = 0; x < info.width; x++) {
    const i = (y * info.width + x) * 3,
      j = (y * info.width + x) * 4,
      [r, g, b] = data.subarray(i, i + 3);
    const alpha =
      r - b > 5 && g - b > 5
        ? Math.max(
            0,
            Math.min(255, Math.round(((255 - b) / (255 - gold[2])) * 255)),
          )
        : 0;
    rgb[j] = gold[0];
    rgb[j + 1] = gold[1];
    rgb[j + 2] = gold[2];
    rgb[j + 3] = alpha;
    if (alpha > 5) {
      left = Math.min(left, x);
      right = Math.max(right, x);
      top = Math.min(top, y);
      bottom = Math.max(bottom, y);
    }
  }
// Remove isolated JPEG colour specks while preserving connected logo strokes.
const visited = new Uint8Array(info.width * info.height);
for (let start = 0; start < visited.length; start++) {
  if (visited[start] || rgb[start * 4 + 3] < 40) continue;
  const queue = [start];
  visited[start] = 1;
  for (let n = 0; n < queue.length; n++) {
    const at = queue[n],
      x = at % info.width,
      y = Math.floor(at / info.width);
    for (let dy = -1; dy <= 1; dy++)
      for (let dx = -1; dx <= 1; dx++) {
        const xx = x + dx,
          yy = y + dy;
        if (xx < 0 || xx >= info.width || yy < 0 || yy >= info.height) continue;
        const next = yy * info.width + xx;
        if (!visited[next] && rgb[next * 4 + 3] >= 40) {
          visited[next] = 1;
          queue.push(next);
        }
      }
  }
  if (queue.length < 12) for (const at of queue) rgb[at * 4 + 3] = 0;
}
for (let at = 0; at < visited.length; at++)
  if (rgb[at * 4 + 3] < 40) rgb[at * 4 + 3] = 0;
const cropped = await sharp(rgb, {
  raw: { width: info.width, height: info.height, channels: 4 },
})
  .extract({ left, top, width: right - left + 1, height: bottom - top + 1 })
  .png()
  .toBuffer();
await mkdir(out, { recursive: true });
await sharp(cropped)
  .resize({ width: 480 })
  .png()
  .toFile(path.join(out, "logo.png"));
await sharp(cropped)
  .resize({ width: 480 })
  .png()
  .toFile(path.join(out, "logo-dark.png"));
// Use brand-specific URLs so a previous logo cannot share their cache keys.
await sharp(cropped).resize({ width: 480 }).png().toFile(path.join(out, "ladyvogue-logo.png"));
await sharp(cropped).resize({ width: 480 }).png().toFile(path.join(out, "ladyvogue-logo-dark.png"));
// The mark occupies the left 37% of this supplied lockup. Include its thread loop,
// but stop before the separate wordmark; the horizontal thread is cropped there.
const mark = await sharp(cropped)
  .extract({
    left: 0,
    top: 0,
    width: Math.round((right - left + 1) * 0.37),
    height: bottom - top + 1,
  })
  .png()
  .toBuffer();
await sharp(mark)
  .resize(512, 512, {
    fit: "contain",
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  })
  .png()
  .toFile(path.join(out, "mark.png"));
for (const size of [32, 180, 512])
  await sharp(mark)
    .resize(size, size, {
      fit: "contain",
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toFile(path.join(out, `favicon-${size}.png`));
await sharp(mark)
  .resize(32, 32, {
    fit: "contain",
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  })
  .png()
  .toFile(path.join(out, "favicon.png"));
const ogLogo = await sharp(cropped).resize({ width: 840 }).png().toBuffer();
await sharp({
  create: { width: 1200, height: 630, channels: 4, background: "#18221f" },
})
  .composite([{ input: ogLogo, gravity: "centre" }])
  .png()
  .toFile(path.join(out, "og-image.png"));
const hex = (c) => "#" + c.map((n) => n.toString(16).padStart(2, "0")).join("");
const luminance = (c) =>
  c
    .map((n) => {
      const v = n / 255;
      return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    })
    .reduce((n, v, i) => n + v * [0.2126, 0.7152, 0.0722][i], 0);
const contrast = (a, b) => {
  const [lo, hi] = [luminance(a), luminance(b)].sort((a, b) => a - b);
  return Number(((hi + 0.05) / (lo + 0.05)).toFixed(2));
};
const palette = {
  gold: hex(gold),
  lightText: "#202820",
  lightLink: "#6b5715",
  darkBackground: "#18221f",
  darkText: "#f5f2e8",
  contrast: {
    darkTextOnGold: contrast(gold, [32, 40, 32]),
    lightLinkOnWhite: contrast([107, 87, 21], [255, 255, 255]),
    goldOnDark: contrast(gold, [24, 34, 31]),
    darkBody: contrast([245, 242, 232], [24, 34, 31]),
  },
  sourceBounds: { left, top, right, bottom },
  sampleMethod:
    "Most frequent gold foreground RGB in supplied raster; alpha derived against white.",
};
await writeFile(
  path.join(root, "scripts/brand/palette.json"),
  JSON.stringify(palette, null, 2) + "\n",
);
const brand = JSON.parse(
  await readFile(path.join(root, "website/content/brand.json"), "utf8"),
);
await writeFile(
  path.join(root, "website/emails/otp.html"),
  `<!-- Generated by scripts/brand/generate.mjs from content/brand.json -->\n<h1>${brand.name}</h1>\n<h2>Your sign-in code</h2>\n<p>Enter this six-digit code to sign in to ${brand.name}:</p>\n<p><strong>{{ .Token }}</strong></p>\n<p>If you did not request this code, you can ignore this email.</p>\n`,
);
console.log(JSON.stringify(palette, null, 2));
