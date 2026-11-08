// Uncompressed LAS 1.0 to 1.4 point clouds for mbmap/3d (ASPRS LAS Specification 1.4 R15): the header,
// VLRs and EVLRs, point data record formats 0 to 10 and the CRS they state. LAZ is refused. Import-free.

/** Caps against hostile files: points kept, (E)VLRs read, and the bytes the 3D worker fetches. */
export const MAX_LAS_POINTS = 10_000_000;
export const MAX_LAS_VLRS = 4096;
export const MAX_LAS_BYTES = 1 << 30;

/** Bytes of each point data record format's own fields; a record may be longer (extra bytes). */
const RECORD_BYTES = [20, 28, 26, 34, 57, 63, 30, 36, 38, 59, 67];
/** Where each format with colors keeps its red, green and blue u16s. */
const RGB_AT: Record<number, number> = { 2: 20, 3: 28, 5: 28, 7: 30, 8: 30, 10: 30 };
/** Header sizes a version needs: 1.3 adds the waveform offset, 1.4 the EVLRs and 64-bit counts. */
const HEADER_BYTES = [227, 227, 227, 235, 375];
const VLR_HEADER = 54;
const EVLR_HEADER = 60;
const GLOBAL_ENCODING_WKT = 16;
const PROJECTION_USER = "LASF_Projection";
const GEO_KEY_DIRECTORY = 34735;
const OGC_WKT = 2112;
const GEOGRAPHIC_TYPE_KEY = 2048;
const PROJECTED_CS_TYPE_KEY = 3072;
const USER_DEFINED = 32767;

/**
 * The CRS a file states: an EPSG code from its GeoTIFF keys or its WKT's top-level authority (a compound
 * CRS's horizontal one's), and the WKT.
 */
export interface LasCrs {
  epsg?: number;
  wkt?: string;
}

/**
 * A LAS file's points, `kept` of its `count`: `recordLength` bytes per record (extra bytes included),
 * `positions` x, y, z per point (scaled and offset, as doubles), `colors` r, g, b per point (8-bit; null
 * for formats without colors), `classification` the class alone (formats 0 to 5 keep flags in its top
 * three bits), `min` and `max` as the header states.
 */
export interface LasCloud {
  version: string;
  pointFormat: number;
  recordLength: number;
  count: number;
  kept: number;
  scale: [number, number, number];
  offset: [number, number, number];
  min: [number, number, number];
  max: [number, number, number];
  positions: Float64Array;
  colors: Uint8Array | null;
  intensity: Uint16Array;
  classification: Uint8Array;
  returnNumber: Uint8Array;
  numberOfReturns: Uint8Array;
  crs: LasCrs | null;
}

function fail(message: string): never {
  throw new Error(`LAS: ${message}`);
}

const ascii = (bytes: Uint8Array, at: number, n: number) => {
  let s = "";
  for (let i = at; i < at + n && bytes[i] !== 0; i++) s += String.fromCharCode(bytes[i]);
  return s;
};

interface VarRecord {
  userId: string;
  recordId: number;
  at: number;
  length: number;
}

/** `n` (E)VLRs from `at` on: each header within the file and its data too. */
function records(bytes: Uint8Array, v: DataView, at: number, n: number, extended: boolean): VarRecord[] {
  if (n > MAX_LAS_VLRS) fail(`more than ${MAX_LAS_VLRS} ${extended ? "EVLRs" : "VLRs"}`);
  const head = extended ? EVLR_HEADER : VLR_HEADER;
  const out: VarRecord[] = [];
  for (let i = 0; i < n; i++) {
    if (at + head > bytes.length) fail(`${extended ? "EVLR" : "VLR"} ${i} beyond the file`);
    const length = extended ? Number(v.getBigUint64(at + 20, true)) : v.getUint16(at + 20, true);
    if (at + head + length > bytes.length) fail(`${extended ? "EVLR" : "VLR"} ${i} data beyond the file`);
    out.push({ userId: ascii(bytes, at + 2, 16), recordId: v.getUint16(at + 18, true), at: at + head, length });
    at += head + length;
  }
  return out;
}

/** The EPSG code of a GeoKeyDirectoryTag: ProjectedCSTypeGeoKey, else GeographicTypeGeoKey (vertical keys ignored). */
function geoKeysEpsg(v: DataView, r: VarRecord): number | undefined {
  if (r.length < 8) return undefined;
  const keys = Math.min(v.getUint16(r.at + 6, true), (r.length - 8) >> 3);
  const found: { [key: number]: number } = {};
  for (let i = 0; i < keys; i++) {
    const at = r.at + 8 + i * 8;
    const [id, location, value] = [v.getUint16(at, true), v.getUint16(at + 2, true), v.getUint16(at + 6, true)];
    if (location === 0 && value > 0 && value < USER_DEFINED) found[id] = value;
  }
  return found[PROJECTED_CS_TYPE_KEY] ?? found[GEOGRAPHIC_TYPE_KEY];
}

/** The EPSG code of WKT's outermost element: an `AUTHORITY["EPSG", n]` (WKT1) or `ID["EPSG", n]` (WKT2) directly inside it. */
export function wktEpsg(wkt: string): number | undefined {
  let depth = 0;
  let quoted = false;
  for (let i = 0; i < wkt.length; i++) {
    const c = wkt[i];
    if (c === '"') quoted = !quoted;
    else if (quoted) continue;
    else if (c === "[" || c === "(") depth++;
    else if (c === "]" || c === ")") depth--;
    else if (depth === 1 && /[A-Za-z]/.test(c) && !/[A-Za-z_]/.test(wkt[i - 1] ?? "")) {
      const m = /^(?:AUTHORITY|ID)\s*[[(]\s*"EPSG"\s*,\s*"?(\d{1,9})"?\s*[\])]/i.exec(wkt.slice(i, i + 64));
      if (m) return Number(m[1]);
    }
  }
  return undefined;
}

/** The horizontal part of a compound CRS (WKT1's COMPD_CS, WKT2's COMPOUNDCRS): its first element; else `wkt`. */
export function horizontalWkt(wkt: string): string {
  if (!/^\s*(COMPD_CS|COMPOUNDCRS)\s*[[(]/i.test(wkt)) return wkt;
  let depth = 0;
  let quoted = false;
  let start = -1;
  for (let i = 0; i < wkt.length; i++) {
    const c = wkt[i];
    if (c === '"') quoted = !quoted;
    else if (quoted) continue;
    else if (c === "[" || c === "(") depth++;
    else if (c === "]" || c === ")") {
      depth--;
      if (depth === 1 && start >= 0) return wkt.slice(start, i + 1);
    } else if (depth === 1 && start < 0 && /[A-Za-z]/.test(c)) start = i;
  }
  return wkt;
}

/**
 * The CRS of the projection records: with the WKT bit of the global encoding set, the OGC WKT record
 * first, else the GeoKeyDirectoryTag first; null when neither gives anything.
 */
function crsOf(bytes: Uint8Array, v: DataView, all: VarRecord[], wktFirst: boolean): LasCrs | null {
  const find = (id: number) => all.find((r) => r.userId === PROJECTION_USER && r.recordId === id);
  const keys = find(GEO_KEY_DIRECTORY);
  const wktRecord = find(OGC_WKT);
  const fromKeys = (): LasCrs | null => {
    const epsg = keys && geoKeysEpsg(v, keys);
    return epsg === undefined ? null : { epsg };
  };
  const fromWkt = (): LasCrs | null => {
    if (!wktRecord) return null;
    const wkt = new TextDecoder().decode(bytes.subarray(wktRecord.at, wktRecord.at + wktRecord.length)).replace(/\0+$/, "").trim();
    if (!wkt) return null;
    const epsg = wktEpsg(horizontalWkt(wkt));
    return epsg === undefined ? { wkt } : { epsg, wkt };
  };
  return wktFirst ? (fromWkt() ?? fromKeys()) : (fromKeys() ?? fromWkt());
}

/**
 * Reads a LAS file. When it holds more than `maxPoints` (at most `MAX_LAS_POINTS`) points, every k-th
 * is kept from the first on, k = ceil(count / maxPoints), as @loaders.gl/las's `skip`. 16-bit colors
 * become 8-bit as loaders.gl's `colorDepth: "auto"` does: divided by 256 when any kept point has a
 * component over 255, else taken as they are (8-bit values stored in 16 bits); loaders.gl decides that
 * per batch of 100,000 points, this over all of them.
 */
export function readLas(bytes: Uint8Array, maxPoints: number): LasCloud {
  if (!(Number.isInteger(maxPoints) && maxPoints > 0)) fail("maxPoints must be a positive integer");
  const limit = Math.min(maxPoints, MAX_LAS_POINTS);
  if (bytes.length < HEADER_BYTES[0] || ascii(bytes, 0, 4) !== "LASF") fail("not a LAS file");
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const [major, minor] = [bytes[24], bytes[25]];
  if (major !== 1 || minor > 4) fail(`version ${major}.${minor} is not supported`);
  const headerSize = v.getUint16(94, true);
  if (headerSize < HEADER_BYTES[minor] || headerSize > bytes.length) fail(`header size ${headerSize} does not fit version 1.${minor}`);
  const pointsAt = v.getUint32(96, true);
  const formatByte = bytes[104];
  if (formatByte & 0xc0) fail("LAZ (compressed LAS) is not supported");
  const pointFormat = formatByte;
  if (pointFormat >= RECORD_BYTES.length) fail(`point data format ${pointFormat} is not supported`);
  const recordLength = v.getUint16(105, true);
  if (recordLength < RECORD_BYTES[pointFormat]) fail(`record length ${recordLength} is shorter than format ${pointFormat}'s ${RECORD_BYTES[pointFormat]} bytes`);
  let count = v.getUint32(107, true);
  if (minor >= 4) {
    const wide = v.getBigUint64(247, true);
    if (wide > BigInt(Number.MAX_SAFE_INTEGER)) fail("point count out of range");
    if (wide > 0n) count = Number(wide);
  }
  const triple = (at: number): [number, number, number] => [v.getFloat64(at, true), v.getFloat64(at + 8, true), v.getFloat64(at + 16, true)];
  const scale = triple(131);
  const offset = triple(155);
  if (![...scale, ...offset].every(Number.isFinite)) fail("scale and offset must be finite");
  const bounds = [179, 187, 195, 203, 211, 219].map((at) => v.getFloat64(at, true));
  const max: [number, number, number] = [bounds[0], bounds[2], bounds[4]];
  const min: [number, number, number] = [bounds[1], bounds[3], bounds[5]];

  const all = records(bytes, v, headerSize, v.getUint32(100, true), false);
  if (minor >= 4) {
    const evlrCount = v.getUint32(243, true);
    if (evlrCount > 0) {
      const evlrAt = v.getBigUint64(235, true);
      if (evlrAt > BigInt(bytes.length)) fail("EVLRs beyond the file");
      all.push(...records(bytes, v, Number(evlrAt), evlrCount, true));
    }
  }
  if (all.some((r) => r.userId === "laszip encoded" && r.recordId === 22204)) fail("LAZ (compressed LAS) is not supported");
  const wktFirst = minor >= 2 && (v.getUint16(6, true) & GLOBAL_ENCODING_WKT) !== 0;
  const crs = crsOf(bytes, v, all, wktFirst);

  if (pointsAt < headerSize) fail("point data inside the header");
  if (pointsAt + count * recordLength > bytes.length) fail(`${count} points of ${recordLength} bytes beyond the file`);
  const step = count > limit ? Math.ceil(count / limit) : 1;
  const kept = Math.ceil(count / step);
  const positions = new Float64Array(kept * 3);
  const intensity = new Uint16Array(kept);
  const classification = new Uint8Array(kept);
  const returnNumber = new Uint8Array(kept);
  const numberOfReturns = new Uint8Array(kept);
  const extended = pointFormat >= 6;
  for (let i = 0; i < kept; i++) {
    const at = pointsAt + i * step * recordLength;
    positions[i * 3] = v.getInt32(at, true) * scale[0] + offset[0];
    positions[i * 3 + 1] = v.getInt32(at + 4, true) * scale[1] + offset[1];
    positions[i * 3 + 2] = v.getInt32(at + 8, true) * scale[2] + offset[2];
    intensity[i] = v.getUint16(at + 12, true);
    const returns = bytes[at + 14];
    returnNumber[i] = extended ? returns & 15 : returns & 7;
    numberOfReturns[i] = extended ? returns >> 4 : (returns >> 3) & 7;
    classification[i] = extended ? bytes[at + 16] : bytes[at + 15] & 31;
  }
  let colors: Uint8Array | null = null;
  const rgbAt = RGB_AT[pointFormat];
  if (rgbAt !== undefined) {
    colors = new Uint8Array(kept * 3);
    let shift = 0;
    for (let i = 0; i < kept && shift === 0; i++) {
      const at = pointsAt + i * step * recordLength + rgbAt;
      if (v.getUint16(at, true) > 255 || v.getUint16(at + 2, true) > 255 || v.getUint16(at + 4, true) > 255) shift = 8;
    }
    for (let i = 0; i < kept; i++) {
      const at = pointsAt + i * step * recordLength + rgbAt;
      for (let c = 0; c < 3; c++) colors[i * 3 + c] = v.getUint16(at + c * 2, true) >> shift;
    }
  }
  return { version: `${major}.${minor}`, pointFormat, recordLength, count, kept, scale, offset, min, max, positions, colors, intensity, classification, returnNumber, numberOfReturns, crs };
}
