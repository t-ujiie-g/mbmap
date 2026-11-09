// Clipping as CesiumJS's planes and polygons, packed for the engine's and mbmap/3d's shaders. Import-free.

/**
 * What `Map.setClipping` takes: `planes` ([nx, ny, nz, d] in east, north, up meters at `origin` [lng, lat, m], at most 16)
 * keep where n·p + d > 0, by any plane or, `unionClippingRegions`, by all; `edgeWidth` pixels by them take `edgeColor`
 * ([r, g, b], 0 to 1); `polygons` (rings of [lng, lat], at most 8 and 64 points) cut inside them, or outside with `inverse`.
 */
export interface Clipping {
  origin: [number, number, number?];
  planes?: [number, number, number, number][];
  unionClippingRegions?: boolean;
  edgeWidth?: number;
  edgeColor?: [number, number, number];
  polygons?: [number, number][][];
  inverse?: boolean;
}

/**
 * `c` as the engine takes it: the origin, union, inverse, edge width and color, the planes (unit normals), then the
 * rings' sizes and vertices in east and north meters at the origin, at the map's scale there (as `Transform::enu_matrix`).
 */
export function packClipping(c: Clipping): number[] {
  const [lng, lat, h = 0] = c.origin;
  const planes = (c.planes ?? []).map(([x, y, z, d]) => {
    const k = Math.hypot(x, y, z);
    return [x / k, y / k, z / k, d / k];
  });
  const rings = c.polygons ?? [];
  const meters = mercatorMeters(lat);
  const my = (y: number) => Math.log(Math.tan(Math.PI / 4 + (y * Math.PI) / 360)) / (2 * Math.PI);
  const verts = rings.flat().flatMap(([x, y]) => [((x - lng) / 360) * meters, (my(y) - my(lat)) * meters]);
  const n = [lng, lat, h, c.unionClippingRegions ? 1 : 0, c.inverse ? 1 : 0, c.edgeWidth ?? 0, ...(c.edgeColor ?? [1, 1, 1]), planes.length, ...planes.flat(), rings.length, ...rings.map((r) => r.length), ...verts];
  if (planes.length > 16 || rings.length > 8 || verts.length > 128 || !n.every(Number.isFinite)) throw new Error("mbmap: setClipping: at most 16 planes, 8 rings and 64 points, all finite");
  return n;
}

/** Meters per mercator unit across at latitude `lat` (degrees), at the map's scale (6371008.8 m Earth). */
export function mercatorMeters(lat: number): number {
  return 2 * Math.PI * 6371008.8 * Math.cos((lat * Math.PI) / 180);
}
