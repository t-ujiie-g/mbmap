// The shapes the draw controller builds from the positions placed, and its
// thresholds, as terra-draw 1.37's defaults. Import-free, so that `npm test` can load it.

export type Position = [number, number];

/** The drawing modes: one click for a point; clicks for vertices; two clicks for a rectangle or a circle; click, move, click for freehand. */
export type DrawMode = "point" | "linestring" | "polygon" | "rectangle" | "circle" | "freehand";

/** CSS pixels from the first or last vertex within which a click closes or finishes (terra-draw's `pointerDistance`). */
export const CLOSE_PIXELS = 40;
/** CSS pixels the pointer moves before freehand adds a vertex (terra-draw's `minDistance`). */
export const FREEHAND_PIXELS = 20;
/** Points of a circle (terra-draw's `segments`). */
export const CIRCLE_STEPS = 64;

/** The rectangle with corners `a` and `b` (in longitude and latitude), from `a` clockwise on screen when `b` is south-east of it. */
export function rectangleRing(a: Position, b: Position): Position[] {
  return [a, [b[0], a[1]], b, [a[0], b[1]], a];
}

/** The GeoJSON geometry of `mode`'s shape through `positions` (a ring is closed here), or null while too few to draw. */
export function geometryOf(mode: DrawMode, positions: Position[]): { type: string; coordinates: unknown } | null {
  if (mode === "point") return positions.length > 0 ? { type: "Point", coordinates: positions[0] } : null;
  if (mode === "linestring") return positions.length > 1 ? { type: "LineString", coordinates: positions } : null;
  if (positions.length < 3) return positions.length === 2 ? { type: "LineString", coordinates: positions } : null;
  const ring = positions[0] === positions.at(-1) ? positions : [...positions, positions[0]];
  return { type: "Polygon", coordinates: [ring] };
}

/** Whether a polygon's vertices make one: at least three, not all on one place. */
export function enoughVertices(mode: DrawMode, positions: Position[]): boolean {
  const distinct = new Set(positions.map((p) => `${p[0]},${p[1]}`)).size;
  return mode === "linestring" ? distinct >= 2 : distinct >= 3;
}

/** Decimals kept in the coordinates of shapes drawn (terra-draw's `coordinatePrecision`; 1e-9° is about 0.1 mm). */
export const PRECISION = 9;

/** `ring` (closed) counter-clockwise in longitude and latitude, as RFC 7946 wants exterior rings. */
export function counterClockwise(ring: Position[]): Position[] {
  let twice = 0;
  for (let i = 0; i + 1 < ring.length; i++) twice += ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1];
  return twice < 0 ? [...ring].reverse() : ring;
}

/** `geometry` with its coordinates rounded to `precision` decimals (0 to 15), outer rings counter-clockwise and holes clockwise (RFC 7946). */
export function finished(geometry: { type: string; coordinates: unknown }, precision = PRECISION): { type: string; coordinates: unknown } {
  const digits = Math.max(0, Math.min(15, Math.round(precision)));
  const round = (p: Position): Position => [Number(p[0].toFixed(digits)), Number(p[1].toFixed(digits))];
  const polygon = (rings: Position[][]) =>
    rings.map((r, i) => {
      const ccw = counterClockwise(r.map(round));
      return i === 0 ? ccw : [...ccw].reverse();
    });
  const c = geometry.coordinates as any;
  const coordinates = {
    Point: () => round(c),
    MultiPoint: () => c.map(round),
    LineString: () => c.map(round),
    MultiLineString: () => c.map((l: Position[]) => l.map(round)),
    Polygon: () => polygon(c),
    MultiPolygon: () => c.map(polygon),
  }[geometry.type as "Point"]?.();
  return coordinates === undefined ? geometry : { type: geometry.type, coordinates };
}
