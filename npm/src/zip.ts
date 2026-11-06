// Zip archives read from their central directory (PKWARE's APPNOTE): stored and
// deflated entries, inflated by the host's DecompressionStream. ZIP64, split
// archives, encryption and other methods are refused. Import-free for `npm test`.

/** An entry of an archive: its name (directories left out) and inflated size. */
export interface ZipEntry {
  readonly name: string;
  readonly size: number;
}

/** `entries`: most entries an archive may list; `bytes`: most bytes its reads may inflate in all. */
export interface ZipLimits {
  entries?: number;
  bytes?: number;
}

const MAX_ZIP_ENTRIES = 10_000;
const MAX_ZIP_BYTES = 256 * 1024 * 1024;

interface Entry extends ZipEntry {
  flags: number;
  method: number;
  compressed: number;
  at: number;
}

function fail(message: string): never {
  throw new Error(`zip: ${message}`);
}

const utf8 = new TextDecoder("utf-8", { fatal: true });

// UTF-8 when flagged or valid, else Shift_JIS (Japanese tools write names so).
function nameOf(bytes: Uint8Array, flags: number): string {
  if (flags & 0x800) return new TextDecoder().decode(bytes);
  try {
    return utf8.decode(bytes);
  } catch {
    return new TextDecoder("shift_jis").decode(bytes);
  }
}

/** The entries of the archive `bytes` and a reader for them, which inflates each at most `limits.bytes` in all. */
export function readZip(bytes: Uint8Array, limits: ZipLimits = {}): { entries: ZipEntry[]; read(entry: ZipEntry): Promise<Uint8Array> } {
  const { entries: maxEntries = MAX_ZIP_ENTRIES, bytes: maxBytes = MAX_ZIP_BYTES } = limits;
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const n = bytes.length;
  let end = -1;
  for (let i = n - 22; i >= Math.max(0, n - 22 - 0xffff); i--) {
    if (v.getUint32(i, true) === 0x06054b50) {
      end = i;
      break;
    }
  }
  if (end < 0) fail("not a zip archive");
  const count = v.getUint16(end + 10, true);
  const at = v.getUint32(end + 16, true);
  if (count === 0xffff || at === 0xffffffff) fail("ZIP64 archives are not supported");
  if (v.getUint16(end + 4, true) !== 0 || v.getUint16(end + 8, true) !== count) fail("split archives are not supported");
  if (count > maxEntries) fail(`more than ${maxEntries} entries`);
  const entries: Entry[] = [];
  let p = at;
  for (let i = 0; i < count; i++) {
    if (p + 46 > end || v.getUint32(p, true) !== 0x02014b50) fail("a malformed central directory");
    const [names, extra, comment] = [28, 30, 32].map((o) => v.getUint16(p + o, true));
    if (p + 46 + names > end) fail("a malformed central directory");
    const name = nameOf(bytes.subarray(p + 46, p + 46 + names), v.getUint16(p + 8, true));
    const entry = {
      name,
      flags: v.getUint16(p + 8, true),
      method: v.getUint16(p + 10, true),
      compressed: v.getUint32(p + 20, true),
      size: v.getUint32(p + 24, true),
      at: v.getUint32(p + 42, true),
    };
    if (!name.endsWith("/")) entries.push(entry);
    p += 46 + names + extra + comment;
  }
  let left = maxBytes;
  async function read(e: ZipEntry): Promise<Uint8Array> {
    const entry = e as Entry;
    if (!entries.includes(entry)) fail("not an entry of this archive");
    if (entry.flags & 1) fail(`${entry.name}: encrypted entries are not supported`);
    if (entry.method !== 0 && entry.method !== 8) fail(`${entry.name}: compression method ${entry.method} is not supported`);
    if (entry.size === 0xffffffff || entry.compressed === 0xffffffff) fail("ZIP64 archives are not supported");
    if (entry.size > left) fail(`the archive inflates to more than ${maxBytes} bytes`);
    const h = entry.at;
    if (h + 30 > n || v.getUint32(h, true) !== 0x04034b50) fail(`${entry.name}: a malformed local header`);
    const data = h + 30 + v.getUint16(h + 26, true) + v.getUint16(h + 28, true);
    if (data + entry.compressed > n) fail(`${entry.name}: data past the end of the archive`);
    const raw = bytes.subarray(data, data + entry.compressed);
    left -= entry.size;
    if (entry.method === 0) {
      if (entry.compressed !== entry.size) fail(`${entry.name}: a stored entry of the wrong size`);
      return raw.slice();
    }
    const out = new Uint8Array(entry.size);
    let got = 0;
    const reader = new Blob([raw as Uint8Array<ArrayBuffer>]).stream().pipeThrough(new DecompressionStream("deflate-raw")).getReader();
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        if (got + value.length > out.length) fail(`${entry.name}: inflates past the size it gives`);
        out.set(value, got);
        got += value.length;
      }
    } catch (err) {
      await reader.cancel().catch(() => {});
      throw err instanceof Error && err.message.startsWith("zip:") ? err : new Error(`zip: ${entry.name}: invalid deflate data`);
    }
    if (got !== out.length) fail(`${entry.name}: inflates short of the size it gives`);
    return out;
  }
  return { entries, read };
}
