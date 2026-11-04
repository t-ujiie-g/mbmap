// Style images (MapLibre's `addImage`): what a page may pass, as straight RGBA pixels.

/** Pixels of a style image: straight (not premultiplied) RGBA rows, `width` x `height`. */
export interface ImagePixels {
  width: number;
  height: number;
  data: Uint8Array;
}

/** What `addImage` takes: ImageData, raw RGBA, or something a 2D canvas can draw (an image, bitmap or canvas). */
export type ImageInput =
  | ImagePixels
  | { width: number; height: number; data: Uint8Array | Uint8ClampedArray }
  | ImageData
  | CanvasImageSource;

/** Options of `addImage`: pixels per CSS pixel and whether the alpha is a distance field colored by paint. */
export interface StyleImageOptions {
  pixelRatio?: number;
  sdf?: boolean;
}

/** `image`'s pixels; `draw` reads one a canvas draws (left to the caller, as it needs the DOM). */
export function imagePixels(image: ImageInput, draw: (image: CanvasImageSource) => ImagePixels): ImagePixels {
  const raw = image as { width?: unknown; height?: unknown; data?: unknown };
  if (raw.data instanceof Uint8Array || raw.data instanceof Uint8ClampedArray) {
    const { width, height } = raw as { width: number; height: number };
    if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0 || raw.data.length !== width * height * 4) {
      throw new Error(`mbmap: image data must be width * height * 4 bytes`);
    }
    return { width, height, data: new Uint8Array(raw.data.buffer, raw.data.byteOffset, raw.data.length) };
  }
  return draw(image as CanvasImageSource);
}

/** `pixelRatio` and `sdf` checked: a positive finite ratio, 1 by default. */
export function imageOptions(options: StyleImageOptions = {}): { pixelRatio: number; sdf: boolean } {
  const pixelRatio = options.pixelRatio ?? 1;
  if (!(pixelRatio > 0 && Number.isFinite(pixelRatio))) throw new Error(`mbmap: pixelRatio must be a positive number: ${pixelRatio}`);
  return { pixelRatio, sdf: options.sdf === true };
}

/** A sprite's entry, as its JSON index gives it. */
interface SpriteEntry {
  x: number;
  y: number;
  width: number;
  height: number;
  pixelRatio?: number;
  sdf?: boolean;
}

/** Most images taken from one sprite. */
export const MAX_SPRITE_IMAGES = 10000;
/** Largest image the pattern and icon atlas holds with its 1 px padding (render_webgl2/pattern_atlas.mbt). */
export const MAX_SPRITE_WIDTH = 1022;
export const MAX_SPRITE_HEIGHT = 4094;

/**
 * The images of a sprite sheet: each entry of `index` cut out of `sheet` (its pixels), named
 * with `prefix` (MapLibre's `id:` for a sprite of several). Entries outside the sheet or too large
 * for the atlas are left out, and so is anything past `MAX_SPRITE_IMAGES` or twice the sheet's bytes.
 */
export function spriteImages(index: unknown, sheet: ImagePixels, prefix: string): { name: string; pixels: ImagePixels; pixelRatio: number; sdf: boolean }[] {
  if (!index || typeof index !== "object") throw new Error("mbmap: a sprite index must be a JSON object");
  const out = [];
  let budget = sheet.data.length * 2;
  for (const [name, e] of Object.entries(index as Record<string, SpriteEntry>)) {
    const { x, y, width, height } = e ?? ({} as SpriteEntry);
    if (![x, y, width, height].every(Number.isInteger) || width <= 0 || height <= 0 || x < 0 || y < 0 || x + width > sheet.width || y + height > sheet.height) {
      continue;
    }
    if (width > MAX_SPRITE_WIDTH || height > MAX_SPRITE_HEIGHT) continue;
    budget -= width * height * 4;
    if (budget < 0 || out.length >= MAX_SPRITE_IMAGES) break;
    const data = new Uint8Array(width * height * 4);
    for (let row = 0; row < height; row++) {
      const from = ((y + row) * sheet.width + x) * 4;
      data.set(sheet.data.subarray(from, from + width * 4), row * width * 4);
    }
    const ratio = typeof e.pixelRatio === "number" && e.pixelRatio > 0 ? e.pixelRatio : 1;
    out.push({ name: prefix + name, pixels: { width, height, data }, pixelRatio: ratio, sdf: e.sdf === true });
  }
  return out;
}

/** The sprites a style's `sprite` names: one URL (named "default"), or a list of `{id, url}`. */
/** A sprite sheet's file: `suffix` and `ext` added to the path, before any query (MapLibre's `normalizeSpriteURL`). */
export function spriteUrl(at: string, suffix: string, ext: string): string {
  const u = new URL(at);
  u.pathname += suffix + ext;
  return u.href;
}

export function spriteList(sprite: unknown): { id: string; url: string }[] {
  if (typeof sprite === "string") return [{ id: "default", url: sprite }];
  if (!Array.isArray(sprite)) return [];
  return sprite.filter((s) => s && typeof s.id === "string" && typeof s.url === "string");
}

/** Draws `image` into a canvas and reads its pixels back, unpremultiplied. */
export function canvasPixels(image: CanvasImageSource): ImagePixels {
  const width = (image as { width: number }).width;
  const height = (image as { height: number }).height;
  const canvas = new OffscreenCanvas(width, height);
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) throw new Error("mbmap: no 2D canvas to read images");
  ctx.drawImage(image, 0, 0);
  const d = ctx.getImageData(0, 0, width, height).data;
  return { width, height, data: new Uint8Array(d.buffer, d.byteOffset, d.length) };
}
