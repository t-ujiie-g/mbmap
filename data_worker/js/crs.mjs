// Table bytes (docs/FORMATS.md "Table") taken to longitude and latitude through
// proj.wasm (proj_worker): each row from its SRID, or from the CRS the data does
// not state otherwise. Imports nothing.

const decoder = new TextDecoder();

function inputTo(exports, bytes) {
  const addr = exports.prepare_input(bytes.length);
  if (addr < 0) throw new Error(`input too large (${bytes.length} bytes)`);
  new Uint8Array(exports.memory.buffer, addr, bytes.length).set(bytes);
}

function checked(exports, n) {
  if (n < 0) {
    const at = exports.output_addr();
    throw new Error(n === -2 ? "out of memory" : decoder.decode(new Uint8Array(exports.memory.buffer, at, -n)));
  }
  return n;
}

// Definitions made in each proj.wasm instance, by their slots.
const defined = new WeakMap();

// proj.wasm's id for `crs`: an EPSG code it knows, a definition made there (handle h
// is -1 - h), or for a .prj's `{ code, definition }` the code if known, else the definition.
function crsId(proj, crs) {
  if (typeof crs === "number") {
    checked(proj, proj.crs_kind(crs));
    return crs;
  }
  if (crs instanceof Float64Array) {
    const made = defined.get(proj) ?? new Map();
    defined.set(proj, made);
    const key = crs.join();
    if (!made.has(key)) {
      inputTo(proj, new Uint8Array(crs.buffer, crs.byteOffset, crs.byteLength));
      made.set(key, -1 - checked(proj, proj.define_crs()));
    }
    return made.get(key);
  }
  if (crs.code !== undefined && (!crs.definition || proj.crs_kind(crs.code) >= 0)) return crsId(proj, crs.code);
  return crsId(proj, crs.definition);
}

const lonLat = (crs) => crs === undefined || crs === 4326;

/**
 * Takes the coordinates of `table` (an ArrayBuffer, changed in place) to EPSG:4326: rows whose
 * `srids` entry is not 0 from that EPSG code, the others from `fallback` (an EPSG code, a definition,
 * a .prj's `{ code, definition }`, or undefined for 4326). `proj()` gives proj.wasm's exports.
 */
export async function toLonLat(table, srids, fallback, proj) {
  const keys = new Set(srids ?? []);
  keys.delete(0);
  if (!srids || srids.includes(0)) keys.add(0);
  if ([...keys].every((k) => (k === 0 ? lonLat(fallback) : k === 4326))) return table;
  const v = new DataView(table);
  const [f, p, r, n] = [0, 4, 8, 12].map((at) => v.getUint32(at, true));
  const ends = 20 + ((f + 3) & ~3);
  const end = (i, base) => (i < 0 ? 0 : v.getUint32(base + i * 4, true));
  const coordsAt = ends + (f + p + r) * 4;
  const rows = new Map();
  for (let i = 0; i < f; i++) {
    const [ps, pe] = [end(i - 1, ends), end(i, ends)];
    if (pe <= ps) continue;
    const [rs, re] = [end(ps - 1, ends + f * 4), end(pe - 1, ends + f * 4)];
    const key = srids?.[i] ?? 0;
    const list = rows.get(key) ?? [];
    list.push(end(rs - 1, ends + (f + p) * 4), end(re - 1, ends + (f + p) * 4));
    rows.set(key, list);
  }
  const exports = await proj();
  const bytes = new Uint8Array(table);
  for (const [key, list] of rows) {
    const crs = key === 0 ? fallback : key;
    if (lonLat(crs)) continue;
    let count = 0;
    for (let i = 0; i < list.length; i += 2) count += list[i + 1] - list[i];
    const xy = new Uint8Array(count * 16);
    for (let i = 0, at = 0; i < list.length; i += 2) {
      const len = (list[i + 1] - list[i]) * 16;
      xy.set(bytes.subarray(coordsAt + list[i] * 16, coordsAt + list[i] * 16 + len), at);
      at += len;
    }
    let out;
    try {
      const id = crsId(exports, crs);
      inputTo(exports, xy);
      const m = checked(exports, exports.transform_coords(id, 4326));
      out = new Float64Array(exports.memory.buffer.slice(exports.output_addr(), exports.output_addr() + m * 8));
    } catch (err) {
      throw key === 0 ? err : new Error(`SRID ${key}: ${err.message}`);
    }
    if (out.some(Number.isNaN)) throw new Error(`coordinates out of reach of ${key === 0 ? "the CRS" : `SRID ${key}`}`);
    const outBytes = new Uint8Array(out.buffer);
    for (let i = 0, at = 0; i < list.length; i += 2) {
      const len = (list[i + 1] - list[i]) * 16;
      bytes.set(outBytes.subarray(at, at + len), coordsAt + list[i] * 16);
      at += len;
    }
  }
  return table;
}
