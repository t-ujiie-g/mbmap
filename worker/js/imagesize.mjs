// An image's size read from its header, so an oversized picture is refused
// before it is decoded (AGENTS.md §8.2). Import-free.

const u16be = (b, i) => (b[i] << 8) | b[i + 1];
const u32be = (b, i) => ((b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]) >>> 0;
const u16le = (b, i) => b[i] | (b[i + 1] << 8);
const ascii = (b, i, s) => [...s].every((c, k) => b[i + k] === c.charCodeAt(0));

// JPEG's SOF markers: C0-CF but DHT (C4), JPG (C8) and DAC (CC).
const isSof = (m) => m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc;

function jpegSize(b) {
  let i = 2;
  while (i + 9 <= b.length) {
    if (b[i] !== 0xff) return null;
    const m = b[i + 1];
    if (m === 0xff) {
      i++;
    } else if (m === 0x01 || (m >= 0xd0 && m <= 0xd8)) {
      i += 2;
    } else if (m === 0xd9 || m === 0xda) {
      return null;
    } else if (isSof(m)) {
      return { width: u16be(b, i + 7), height: u16be(b, i + 5) };
    } else {
      i += 2 + u16be(b, i + 2);
    }
  }
  return null;
}

// WebP: the first chunk, "VP8 " (lossy), "VP8L" (lossless) or "VP8X" (extended, its canvas).
function webpSize(b) {
  if (b.length < 30) return null;
  if (ascii(b, 12, "VP8 ") && b[23] === 0x9d && b[24] === 0x01 && b[25] === 0x2a) {
    return { width: u16le(b, 26) & 0x3fff, height: u16le(b, 28) & 0x3fff };
  }
  if (ascii(b, 12, "VP8L") && b[20] === 0x2f) {
    const bits = (b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24)) >>> 0;
    return { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 };
  }
  if (ascii(b, 12, "VP8X")) {
    return { width: (b[24] | (b[25] << 8) | (b[26] << 16)) + 1, height: (b[27] | (b[28] << 8) | (b[29] << 16)) + 1 };
  }
  return null;
}

/** The width and height a PNG, JPEG, WebP or GIF header in `bytes` gives; null for anything else. */
export function imageSize(bytes) {
  const b = bytes;
  if (b.length >= 24 && b[0] === 0x89 && ascii(b, 1, "PNG\r\n\x1a\n") && ascii(b, 12, "IHDR")) {
    return { width: u32be(b, 16), height: u32be(b, 20) };
  }
  if (b.length >= 4 && b[0] === 0xff && b[1] === 0xd8) return jpegSize(b);
  if (b.length >= 16 && ascii(b, 0, "RIFF") && ascii(b, 8, "WEBP")) return webpSize(b);
  if (b.length >= 10 && ascii(b, 0, "GIF8")) return { width: u16le(b, 6), height: u16le(b, 8) };
  return null;
}

/** Throws when `bytes`' header gives a side over `max`; a format it cannot read is left to the decoder. */
export function checkImageSize(bytes, max, what = "image") {
  const size = imageSize(bytes);
  if (size && (size.width > max || size.height > max)) {
    throw new Error(`${what} is ${size.width} x ${size.height}, over ${max}`);
  }
}

// Bytes of a Blob read for its header: JPEG's SOF may follow tens of KB of EXIF.
const HEADER_BYTES = 256 * 1024;

/** `checkImageSize` for a Blob, reading only its first bytes. */
export async function checkBlobImageSize(blob, max, what = "image") {
  checkImageSize(new Uint8Array(await blob.slice(0, HEADER_BYTES).arrayBuffer()), max, what);
}
