// Rendered-feature query results in MapLibre GL JS 6.16.0's order (query_features.ts,
// style.ts), BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.
// Imports only camera.ts (by its extension), so that `npm test` can load it.
import { type PointLike, toPoint } from "./camera.ts";

/** A GeoJSON feature as a query returns it. */
export interface GeoJSONFeature {
  type: "Feature";
  id?: number | string;
  geometry: { type: string; coordinates: unknown } | null;
  properties: Record<string, unknown>;
}

/** One tile's answer from the engine: each hit's layer id, feature index, depth (extrusions) and feature. */
export interface TileResult {
  z: number;
  x: number;
  y: number;
  hits: { layer: string | number; index: number; distance: number; feature: GeoJSONFeature }[];
}

/** A query's screen geometry: one point, or a box as a closed ring (MapLibre's box query). */
export function queryPoints(geometry: QueryGeometry, width: number, height: number): number[] {
  if (geometry === null) return queryPoints([[0, 0], [width, height]], width, height);
  if (typeof geometry[0] === "number") return [geometry[0], geometry[1] as number];
  const [[x0, y0], [x1, y1]] = geometry as [[number, number], [number, number]];
  return [x0, y0, x1, y0, x1, y1, x0, y1, x0, y0];
}

/**
 * The hits of `tiles` in MapLibre's order: top layer first, each layer's features by tile (zoom,
 * row, column), last drawn first, once per tile; extrusions, which hide one another, nearest first
 * wherever the first of their layers stands.
 */
export function orderRendered(tiles: TileResult[], layers: { id: string; type: string }[]): { layer: string; feature: GeoJSONFeature }[] {
  const sorted = [...tiles].sort((a, b) => a.z - b.z || a.y - b.y || a.x - b.x);
  const byLayer = new Map<string, { index: number; distance: number; feature: GeoJSONFeature }[]>();
  for (const t of sorted) {
    const seen = new Set<string>();
    const ofTile = new Map<string, { index: number; distance: number; feature: GeoJSONFeature }[]>();
    for (const h of t.hits) {
      if (typeof h.layer !== "string") continue;
      const key = `${h.layer}/${h.index}`;
      if (seen.has(key)) continue;
      seen.add(key);
      let list = ofTile.get(h.layer);
      if (!list) ofTile.set(h.layer, (list = []));
      list.push(h);
    }
    for (const [layer, list] of ofTile) {
      list.sort((a, b) => b.index - a.index);
      let all = byLayer.get(layer);
      if (!all) byLayer.set(layer, (all = []));
      all.push(...list);
    }
  }
  const is3D = (id: string) => layers.find((l) => l.id === id)?.type === "fill-extrusion";
  const position = new Map(layers.map((l, i) => [l.id, i]));
  const features3D: { layer: string; distance: number; feature: GeoJSONFeature }[] = [];
  for (let l = layers.length - 1; l >= 0; l--) {
    if (!is3D(layers[l].id)) continue;
    for (const h of byLayer.get(layers[l].id) ?? []) features3D.push({ layer: layers[l].id, distance: h.distance, feature: h.feature });
  }
  // Faces at one depth computed from different vertices (a building and its outline) differ by
  // rounding: they count as exact ties, which the sort keeps in order.
  features3D.sort((a, b) => (Math.abs(a.distance - b.distance) <= 1e-9 * Math.abs(a.distance) ? 0 : b.distance - a.distance));
  const out: { layer: string; feature: GeoJSONFeature }[] = [];
  for (let l = layers.length - 1; l >= 0; l--) {
    const id = layers[l].id;
    if (is3D(id)) {
      while (features3D.length > 0 && (position.get(features3D[features3D.length - 1].layer) ?? -1) >= l) {
        const f = features3D.pop()!;
        out.push({ layer: f.layer, feature: f.feature });
      }
    } else {
      for (const h of byLayer.get(id) ?? []) out.push({ layer: id, feature: h.feature });
    }
  }
  return out;
}

/** A query's screen geometry as `queryPoints` takes it: a point or a box, null for the whole map. */
export type QueryGeometry = [number, number] | [[number, number], [number, number]] | null;

/**
 * `queryRenderedFeatures`'s arguments as MapLibre reads them: a point or a box (CSS pixels),
 * then the options, which may also come alone.
 */
export function queryArgs<O extends object>(geometryOrOptions: PointLike | [PointLike, PointLike] | O | undefined, options: O | undefined): { geometry: QueryGeometry; options: Partial<O> } {
  const isPoint = (g: unknown) => (Array.isArray(g) ? typeof g[0] === "number" : typeof (g as { x?: unknown })?.x === "number");
  const pair = (q: PointLike): [number, number] => {
    const p = toPoint(q);
    return [p.x, p.y];
  };
  if (geometryOrOptions !== undefined && (Array.isArray(geometryOrOptions) || isPoint(geometryOrOptions))) {
    const geometry: QueryGeometry = isPoint(geometryOrOptions)
      ? pair(geometryOrOptions as PointLike)
      : [pair((geometryOrOptions as [PointLike, PointLike])[0]), pair((geometryOrOptions as [PointLike, PointLike])[1])];
    return { geometry, options: options ?? {} };
  }
  return { geometry: null, options: (geometryOrOptions as O | undefined) ?? options ?? {} };
}

/** The `layers` option as a list (null for all), or why it is refused: not an Array or Set, or naming a layer `has` lacks. */
export function queryLayers(layers: unknown, has: (id: string) => boolean): string[] | null | Error {
  if (layers === undefined) return null;
  if (!Array.isArray(layers) && !(layers instanceof Set)) return new Error("mbmap: layers must be an Array or a Set of strings");
  const list = [...(layers as Iterable<string>)];
  const missing = list.find((id) => !has(id));
  if (missing !== undefined) return new Error(`mbmap: the layer '${missing}' does not exist in the map's style and cannot be queried for features`);
  return list;
}
