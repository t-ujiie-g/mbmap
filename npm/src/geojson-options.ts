// What a GeoJSON source's specification and cluster queries become in messages to its
// worker. Import-free, so that `npm test` can load it.

/** A cluster query: the expansion zoom, the children or the leaves (`limit`, `offset`) of cluster `cluster`. */
export type ClusterQuery =
  | { op: "expansion" | "children"; cluster: number }
  | { op: "leaves"; cluster: number; limit?: number; offset?: number };

const INT32_MAX = 2 ** 31 - 1;

/** The options the worker loads a source with, derived as MapLibre's GeoJSONSource does (`clusterMaxZoom` 0 or unset means `maxzoom` - 1). */
export function loadOptions(spec: Record<string, unknown>) {
  const num = (v: unknown, d: number) => (typeof v === "number" ? v : d);
  const maxzoom = num(spec.maxzoom, 18);
  const clusterMaxZoom = num(spec.clusterMaxZoom, 0);
  const cluster =
    spec.cluster === true
      ? {
          maxZoom: Math.max(-1, Math.min(30, clusterMaxZoom ? Math.round(clusterMaxZoom) : maxzoom - 1)),
          radius: num(spec.clusterRadius, 0) || 50,
          minPoints: Math.min(INT32_MAX, Math.ceil(Math.max(2, num(spec.clusterMinPoints, 0) || 2))),
        }
      : null;
  return { maxzoom, buffer: num(spec.buffer, 128), tolerance: num(spec.tolerance, 0.375), lineMetrics: spec.lineMetrics === true, cluster };
}

/** Whether two specifications load the same: the same data (by identity) and options. */
export function sameOptions(a: Record<string, unknown>, b: Record<string, unknown>): boolean {
  return a.data === b.data && JSON.stringify(loadOptions(a)) === JSON.stringify(loadOptions(b));
}

/**
 * `query` as the worker takes it: integer ids, a `limit` of 0 (MapLibre's 10), more or
 * Infinity (-1), an `offset` from 0. Throws on anything else.
 */
export function clusterArgs(query: ClusterQuery) {
  const { cluster } = query;
  if (!Number.isInteger(cluster) || Math.abs(cluster) > INT32_MAX) throw new Error(`mbmap: no cluster with the id ${cluster}`);
  if (query.op !== "leaves") return query;
  const limit = query.limit ?? 10;
  const offset = query.offset ?? 0;
  if (!(limit === Infinity || (Number.isInteger(limit) && limit >= 0))) throw new Error(`mbmap: bad limit ${limit}`);
  if (!(Number.isInteger(offset) && offset >= 0)) throw new Error(`mbmap: bad offset ${offset}`);
  return { op: "leaves", cluster, limit: limit > INT32_MAX ? -1 : limit, offset: Math.min(offset, INT32_MAX) };
}
