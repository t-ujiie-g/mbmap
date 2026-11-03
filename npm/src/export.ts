// `Map.toBlob`'s joining and encoding, loaded with its first call. Import-free.

/** The largest image made: what Chromium and Safari let a canvas hold. */
const MAX_IMAGE_SIDE = 32767;
const MAX_IMAGE_PIXELS = 16384 * 16384;

/**
 * A `width` x `height` image drawn by `region` (the RGBA of a part) in parts of up to `side`
 * pixels a side, joined in a 2D canvas and encoded as `type`.
 */
export function encodeImage(
  width: number,
  height: number,
  side: number,
  region: (x: number, y: number, w: number, h: number) => Uint8ClampedArray<ArrayBuffer>,
  type?: string,
  quality?: number,
): Promise<Blob> {
  if (width < 1 || height < 1 || width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE || width * height > MAX_IMAGE_PIXELS) {
    throw new Error(`mbmap: cannot make a ${width} x ${height} image`);
  }
  const out = document.createElement("canvas");
  out.width = width;
  out.height = height;
  const ctx = out.getContext("2d");
  if (!ctx) throw new Error("mbmap: no 2D canvas for the image");
  for (let y = 0; y < height; y += side) {
    for (let x = 0; x < width; x += side) {
      const w = Math.min(side, width - x);
      const h = Math.min(side, height - y);
      ctx.putImageData(new ImageData(region(x, y, w, h), w, h), x, y);
    }
  }
  return new Promise((resolve, reject) => {
    out.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("mbmap: the image could not be encoded"))), type, quality);
  });
}
