// The KML of a KMZ: `doc.kml` at the top of the zip, else its first `.kml` entry.
// A minimal zip reader of its own (stored and deflated entries, no zip64 or
// encryption), every offset and size checked; inflated by `DecompressionStream`.

const u16 = (b, at) => b[at] | (b[at + 1] << 8);
const u32 = (b, at) => (b[at] | (b[at + 1] << 8) | (b[at + 2] << 16)) + b[at + 3] * 0x1000000;

/** Whether `bytes` start as a zip's local file header does (`PK\3\4`). */
export const isZip = (bytes) => bytes.length >= 4 && bytes[0] === 0x50 && bytes[1] === 0x4b && bytes[2] === 3 && bytes[3] === 4;

/**
 * The entries of the zip `bytes` from its central directory: `{ name, method, flags, size, start, end }`
 * with `start`..`end` the entry's stored bytes. Throws on a malformed zip.
 */
export function zipEntries(bytes) {
  const fail = (why) => {
    throw new Error(`malformed zip: ${why}`);
  };
  // The end of central directory record: 22 bytes and a comment of up to 65535.
  let eocd = -1;
  for (let at = bytes.length - 22; at >= 0 && at >= bytes.length - 22 - 0xffff; at--) {
    if (u32(bytes, at) === 0x06054b50) {
      eocd = at;
      break;
    }
  }
  if (eocd < 0) fail("no end of central directory");
  const count = u16(bytes, eocd + 10);
  let at = u32(bytes, eocd + 16);
  const decoder = new TextDecoder();
  const entries = [];
  for (let i = 0; i < count; i++) {
    if (at + 46 > eocd || u32(bytes, at) !== 0x02014b50) fail("bad central directory entry");
    const flags = u16(bytes, at + 8);
    const method = u16(bytes, at + 10);
    const compressed = u32(bytes, at + 20);
    const size = u32(bytes, at + 24);
    const [n, e, c] = [u16(bytes, at + 28), u16(bytes, at + 30), u16(bytes, at + 32)];
    const local = u32(bytes, at + 42);
    if (at + 46 + n + e + c > eocd) fail("bad central directory entry");
    const name = decoder.decode(bytes.subarray(at + 46, at + 46 + n));
    if (local + 30 > bytes.length || u32(bytes, local) !== 0x04034b50) fail(`bad local header for ${name}`);
    const start = local + 30 + u16(bytes, local + 26) + u16(bytes, local + 28);
    if (start + compressed > bytes.length) fail(`${name} runs past the end`);
    entries.push({ name, method, flags, size, start, end: start + compressed });
    at += 46 + n + e + c;
  }
  return entries;
}

/** An entry's bytes, inflated if deflated; refused past `max` bytes. */
export async function entryBytes(bytes, entry, max) {
  if (entry.flags & 1) throw new Error(`${entry.name} is encrypted`);
  const data = bytes.subarray(entry.start, entry.end);
  if (entry.method === 0) {
    if (data.length > max) throw new Error(`${entry.name} is larger than ${max} bytes`);
    return data;
  }
  if (entry.method !== 8) throw new Error(`${entry.name} uses compression method ${entry.method}`);
  const reader = new Blob([data]).stream().pipeThrough(new DecompressionStream("deflate-raw")).getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > max) {
      await reader.cancel();
      throw new Error(`${entry.name} inflates past ${max} bytes`);
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.length;
  }
  return out;
}

/** The KML a KMZ holds: `doc.kml` at its top, else its first `.kml` entry, at most `max` bytes. */
export async function kmlOfKmz(bytes, max) {
  const kml = zipEntries(bytes).filter((e) => /\.kml$/i.test(e.name));
  const entry = kml.find((e) => e.name.toLowerCase() === "doc.kml") ?? kml[0];
  if (!entry) throw new Error("the KMZ holds no .kml file");
  return entryBytes(bytes, entry, max);
}
