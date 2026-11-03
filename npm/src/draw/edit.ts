// Editing a drawn geometry: its vertices and the midpoints between them, a
// vertex moved, inserted or deleted, the whole moved, and the nearest point of
// a segment for snapping. Import-free, so that `npm test` can load it.
import type { Position } from "./shapes";

export interface Geometry {
  type: string;
  coordinates: unknown;
}

/** Where a vertex lies: its ring (0 for a line or a point) and index. */
export interface At {
  ring: number;
  index: number;
}

/** The rings of `g` as arrays of positions (a point's one position, a line as one ring); rings stay closed. */
function rings(g: Geometry): Position[][] {
  if (g.type === "Point") return [[g.coordinates as Position]];
  if (g.type === "LineString") return [g.coordinates as Position[]];
  return g.coordinates as Position[][];
}

function rebuild(g: Geometry, rs: Position[][]): Geometry {
  if (g.type === "Point") return { type: "Point", coordinates: rs[0][0] };
  if (g.type === "LineString") return { type: "LineString", coordinates: rs[0] };
  return { type: g.type, coordinates: rs };
}

const closed = (g: Geometry) => g.type === "Polygon";

/** Each vertex once (a ring's closing copy left out). */
export function vertices(g: Geometry): { at: At; position: Position }[] {
  return rings(g).flatMap((r, ring) => (closed(g) ? r.slice(0, -1) : r).map((position, index) => ({ at: { ring, index }, position })));
}

/** The midpoint of each edge, with where a vertex inserted there goes (none for a point). */
export function midpoints(g: Geometry): { at: At; position: Position }[] {
  if (g.type === "Point") return [];
  return rings(g).flatMap((r, ring) =>
    r.slice(1).map((b, i) => ({ at: { ring, index: i + 1 }, position: [(r[i][0] + b[0]) / 2, (r[i][1] + b[1]) / 2] as Position })),
  );
}

/** `g` with the vertex `at` at `position` (a ring's first vertex moves its closing copy too). */
export function moveVertex(g: Geometry, at: At, position: Position): Geometry {
  return rebuild(g, rings(g).map((r, ring) => {
    if (ring !== at.ring) return r;
    const next = [...r];
    next[at.index] = position;
    if (closed(g) && at.index === 0) next[next.length - 1] = position;
    return next;
  }));
}

/** `g` with `position` inserted before the vertex `at.index` of ring `at.ring`. */
export function insertVertex(g: Geometry, at: At, position: Position): Geometry {
  if (g.type === "Point") return g;
  return rebuild(g, rings(g).map((r, ring) => (ring === at.ring ? [...r.slice(0, at.index), position, ...r.slice(at.index)] : r)));
}

/** `g` without the vertex `at`, or null when a line would keep fewer than 2 vertices or a ring fewer than 3. */
export function deleteVertex(g: Geometry, at: At): Geometry | null {
  if (g.type === "Point") return null;
  const r = rings(g)[at.ring];
  const open = closed(g) ? r.slice(0, -1) : r;
  if (open.length <= (closed(g) ? 3 : 2)) return null;
  const kept = open.filter((_, i) => i !== at.index);
  const ring = closed(g) ? [...kept, kept[0]] : kept;
  return rebuild(g, rings(g).map((x, i) => (i === at.ring ? ring : x)));
}

/** `g` moved by `dx` degrees of longitude and `dy` of latitude. */
export function translate(g: Geometry, dx: number, dy: number): Geometry {
  return rebuild(g, rings(g).map((r) => r.map(([x, y]) => [x + dx, y + dy] as Position)));
}

/** The point of segment `a`-`b` nearest `p` (all on screen) and how far along it lies (0 to 1). */
export function nearestOnSegment(p: { x: number; y: number }, a: { x: number; y: number }, b: { x: number; y: number }): { x: number; y: number; t: number } {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const len = dx * dx + dy * dy;
  const t = len === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len));
  return { x: a.x + t * dx, y: a.y + t * dy, t };
}

/** Whether screen point `p` lies inside the closed `ring` of screen points (even-odd). */
export function insideRing(p: { x: number; y: number }, ring: { x: number; y: number }[]): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [a, b] = [ring[i], ring[j]];
    if (a.y > p.y !== b.y > p.y && p.x < ((b.x - a.x) * (p.y - a.y)) / (b.y - a.y) + a.x) inside = !inside;
  }
  return inside;
}
