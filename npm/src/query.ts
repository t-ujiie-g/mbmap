// Rendered-feature query results put in MapLibre's order (src/source/query_features.ts
// `mergeRenderedFeatureLayers`, src/style/style.ts `_flattenAndSortRenderedFeatures`
// of MapLibre GL JS 6.16.0, BSD-3-Clause, Copyright (c) 2020, MapLibre contributors;
// see NOTICE). Import-free, so that `npm test` can load it.

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
export function queryPoints(geometry: [number, number] | [[number, number], [number, number]] | null, width: number, height: number): number[] {
  if (geometry === null) return queryPoints([[0, 0], [width, height]], width, height);
  if (typeof geometry[0] === "number") return [geometry[0], geometry[1] as number];
  const [[x0, y0], [x1, y1]] = geometry as [[number, number], [number, number]];
  return [x0, y0, x1, y0, x1, y1, x0, y1, x0, y0];
}

/**
 * The hits of `tiles` as MapLibre orders them: layers from the top of `layers` (bottom first,
 * as in the style) down, each layer's features tile by tile (by zoom, then row, then column) and
 * last drawn first, a feature once per tile; extrusions, which hide one another, nearest first
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
