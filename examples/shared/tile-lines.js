// Lines of `querySourceFeatures` results without the copies tiles keep past their edges.
// Import-free, so that the pack test can load it in Node.

const lngOf = (x, n) => (x / n) * 360 - 180;
const latOf = (y, n) => (360 / Math.PI) * Math.atan(Math.exp((1 - (2 * y) / n) * Math.PI)) - 90;

/** A tile's bounds as [west, south, east, north]. */
export function tileBounds({ z, x, y }) {
  const n = 2 ** z;
  return [lngOf(x, n), latOf(y + 1, n), lngOf(x + 1, n), latOf(y, n)];
}

// Where segment a-b meets `axis` = k, taken from the end with the lower coordinate on `axis`, so
// the two tiles sharing an edge find the same point whichever way their copies of a line run.
function cross(a, b, k, axis) {
  const [p, q] = a[axis] <= b[axis] ? [a, b] : [b, a];
  const other = 1 - axis;
  const out = [0, 0];
  out[axis] = k;
  out[other] = p[other] + ((k - p[axis]) / (q[axis] - p[axis])) * (q[other] - p[other]);
  return out;
}

// The parts of `lines` with lo <= coordinate `axis` <= hi.
function clipAxis(lines, lo, hi, axis) {
  const out = [];
  let piece = [];
  const add = (p) => {
    const last = piece[piece.length - 1];
    if (!last || last[0] !== p[0] || last[1] !== p[1]) piece.push(p);
  };
  const end = () => {
    if (piece.length >= 2) out.push(piece);
    piece = [];
  };
  const inside = (p) => p[axis] >= lo && p[axis] <= hi;
  const edge = (v) => (v < lo ? lo : hi);
  for (const line of lines) {
    for (let i = 0; i < line.length; i++) {
      const p = line[i];
      const q = line[i - 1];
      if (!q || inside(q)) {
        if (inside(p)) add(p);
        else if (q) {
          add(cross(q, p, edge(p[axis]), axis));
          end();
        }
      } else if (inside(p)) {
        add(cross(q, p, edge(q[axis]), axis));
        add(p);
      } else if (edge(q[axis]) !== edge(p[axis])) {
        add(cross(q, p, edge(q[axis]), axis));
        add(cross(q, p, edge(p[axis]), axis));
        end();
      }
    }
    end();
  }
  return out;
}

/** `coordinates` (one line's) cut to `[west, south, east, north]`, as the lines left inside. */
export function clipLine(coordinates, [west, south, east, north]) {
  return clipAxis(clipAxis([coordinates], west, east, 0), south, north, 1);
}

/**
 * The lines of `features` (LineString and MultiLineString, each with its `tile`), each cut to its
 * own tile, from the deepest zoom's tiles only, so a line crossing tiles is in each once.
 */
export function tileLines(features) {
  const lines = features.flatMap((f) =>
    f.geometry?.type === "LineString" ? [[f, f.geometry.coordinates]] : f.geometry?.type === "MultiLineString" ? f.geometry.coordinates.map((c) => [f, c]) : [],
  );
  const z = Math.max(...lines.map(([f]) => f.tile?.z ?? -1));
  return lines.flatMap(([f, c]) => (!f.tile ? [c] : f.tile.z === z ? clipLine(c, tileBounds(f.tile)) : []));
}
