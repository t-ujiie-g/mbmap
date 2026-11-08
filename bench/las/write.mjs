// Writes uncompressed LAS 1.0 to 1.4 files (ASPRS LAS 1.4 R15) for the tests, the golden and the pack
// test's fixture. Import-free.

/** Bytes of each point data record format, and where its colors are. */
export const RECORD_BYTES = [20, 28, 26, 34, 57, 63, 30, 36, 38, 59, 67];
export const RGB_AT = { 2: 20, 3: 28, 5: 28, 7: 30, 8: 30, 10: 30 };
const HEADER_BYTES = [227, 227, 227, 235, 375];

/** A VLR's (or EVLR's) bytes: `userId`, `recordId` and `data`. */
function record({ userId, recordId, data }, extended) {
  const head = extended ? 60 : 54;
  const out = new Uint8Array(head + data.length);
  const v = new DataView(out.buffer);
  for (let i = 0; i < Math.min(16, userId.length); i++) out[2 + i] = userId.charCodeAt(i);
  v.setUint16(18, recordId, true);
  if (extended) v.setBigUint64(20, BigInt(data.length), true);
  else v.setUint16(20, data.length, true);
  out.set(data, head);
  return out;
}

/** A GeoKeyDirectoryTag VLR's data: `keys` as [id, value] pairs, each stored in place. */
export function geoKeys(keys) {
  const data = new Uint8Array(8 + keys.length * 8);
  const v = new DataView(data.buffer);
  [1, 1, 0, keys.length].forEach((n, i) => v.setUint16(i * 2, n, true));
  keys.forEach(([id, value], i) => {
    v.setUint16(8 + i * 8, id, true);
    v.setUint16(8 + i * 8 + 4, 1, true);
    v.setUint16(8 + i * 8 + 6, value, true);
  });
  return { userId: "LASF_Projection", recordId: 34735, data };
}

/** An OGC WKT VLR, null-terminated. */
export const wktRecord = (wkt) => ({ userId: "LASF_Projection", recordId: 2112, data: new TextEncoder().encode(`${wkt}\0`) });

/**
 * A LAS file of version 1.`minor` and point `format`: each point `{x, y, z}` (the stored integers),
 * `intensity`, `returns` (the return byte), `classification`, `flags` (formats 0 to 5: or-ed into the
 * class byte's top bits) and `rgb` (u16s); `extra` bytes after each record, `vlrs`, `evlrs` (1.4),
 * `globalEncoding`, `scale` and `offset`.
 */
export function writeLas({ minor, format, points, scale = [0.01, 0.01, 0.01], offset = [0, 0, 0], extra = 0, vlrs = [], evlrs = [], globalEncoding = 0 }) {
  const headerSize = HEADER_BYTES[minor];
  const vlrBytes = vlrs.map((r) => record(r, false));
  const evlrBytes = evlrs.map((r) => record(r, true));
  const recordLength = RECORD_BYTES[format] + extra;
  const pointsAt = headerSize + vlrBytes.reduce((n, b) => n + b.length, 0);
  const evlrAt = pointsAt + points.length * recordLength;
  const total = evlrAt + evlrBytes.reduce((n, b) => n + b.length, 0);
  const out = new Uint8Array(total);
  const v = new DataView(out.buffer);
  out.set([76, 65, 83, 70], 0);
  if (minor >= 2) v.setUint16(6, globalEncoding, true);
  out[24] = 1;
  out[25] = minor;
  const software = "mbmap bench/las";
  for (let i = 0; i < software.length; i++) out[58 + i] = software.charCodeAt(i);
  v.setUint16(94, headerSize, true);
  v.setUint32(96, pointsAt, true);
  v.setUint32(100, vlrs.length, true);
  out[104] = format;
  v.setUint16(105, recordLength, true);
  v.setUint32(107, format < 6 ? points.length : 0, true);
  scale.forEach((s, i) => v.setFloat64(131 + i * 8, s, true));
  offset.forEach((o, i) => v.setFloat64(155 + i * 8, o, true));
  const lo = [Infinity, Infinity, Infinity];
  const hi = [-Infinity, -Infinity, -Infinity];
  for (const p of points) {
    [p.x, p.y, p.z].forEach((n, i) => {
      const value = n * scale[i] + offset[i];
      lo[i] = Math.min(lo[i], value);
      hi[i] = Math.max(hi[i], value);
    });
  }
  for (let i = 0; i < 3 && points.length > 0; i++) {
    v.setFloat64(179 + i * 16, hi[i], true);
    v.setFloat64(187 + i * 16, lo[i], true);
  }
  if (minor >= 4) {
    if (evlrs.length > 0) v.setBigUint64(235, BigInt(evlrAt), true);
    v.setUint32(243, evlrs.length, true);
    v.setBigUint64(247, BigInt(points.length), true);
  }
  let at = headerSize;
  for (const b of vlrBytes) {
    out.set(b, at);
    at += b.length;
  }
  const extended = format >= 6;
  for (const p of points) {
    v.setInt32(at, p.x, true);
    v.setInt32(at + 4, p.y, true);
    v.setInt32(at + 8, p.z, true);
    v.setUint16(at + 12, p.intensity ?? 0, true);
    out[at + 14] = p.returns ?? 0;
    if (extended) out[at + 16] = p.classification ?? 0;
    else out[at + 15] = ((p.classification ?? 0) & 31) | ((p.flags ?? 0) << 5);
    const rgbAt = RGB_AT[format];
    if (rgbAt !== undefined && p.rgb) p.rgb.forEach((c, i) => v.setUint16(at + rgbAt + i * 2, c, true));
    for (let i = RECORD_BYTES[format]; i < recordLength; i++) out[at + i] = 0xa5;
    at += recordLength;
  }
  for (const b of evlrBytes) {
    out.set(b, at);
    at += b.length;
  }
  return out;
}
