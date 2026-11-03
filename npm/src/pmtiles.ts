// A PMTiles archive's header as a TileJSON-like document (pmtiles 4.5.0's
// `bytesToHeader` layout). Loaded only for `pmtiles://` sources; the display
// worker reads the rest (worker/js/pmtiles.mjs).

/** Tile types of the header's byte 99. */
const TYPES: Record<number, string> = { 1: "mvt", 2: "png", 3: "jpeg", 4: "webp", 5: "avif" };

/** The document for `pmtiles://<archive>`: tiles the worker reads from the archive, its zoom range, bounds and tile type. */
export async function pmtilesDocument(archive: string): Promise<Record<string, unknown>> {
  const res = await fetch(archive, { headers: { Range: "bytes=0-126" }, credentials: "omit" });
  if (!res.ok) throw new Error(`mbmap: PMTiles ${archive}: HTTP ${res.status}`);
  const bytes = new Uint8Array(await res.arrayBuffer());
  if (bytes.length < 127 || new TextDecoder().decode(bytes.subarray(0, 7)) !== "PMTiles" || bytes[7] !== 3) {
    throw new Error(`mbmap: ${archive} is not a PMTiles v3 archive`);
  }
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const deg = (at: number) => v.getInt32(at, true) / 1e7;
  return {
    tiles: [`pmtiles://${archive}/{z}/{x}/{y}`],
    minzoom: v.getUint8(100),
    maxzoom: v.getUint8(101),
    bounds: [deg(102), deg(106), deg(110), deg(114)],
    tileType: TYPES[v.getUint8(99)] ?? "unknown",
  };
}
