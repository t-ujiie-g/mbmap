// The attributions MapLibre GL JS 6.16.0's AttributionControl shows
// (`_updateAttributions`, BSD-3-Clause, Copyright (c) 2020 MapLibre contributors;
// see NOTICE). Import-free, so that `npm test` can load it.

interface StyleLike {
  sources?: Record<string, unknown>;
  layers?: unknown[];
  terrain?: unknown;
}

/** Whether a layer is drawn at `zoom`, as MapLibre's `isHidden` tells it. */
function shown(layer: Record<string, unknown>, zoom: number): boolean {
  const min = Number(layer.minzoom ?? 0);
  const max = Number(layer.maxzoom ?? 0);
  if (min && zoom < min) return false;
  if (max && zoom >= max) return false;
  return (layer.layout as { visibility?: unknown } | undefined)?.visibility !== "none";
}

/**
 * The attributions of the sources a layer shown at `zoom` or the terrain uses, in source order,
 * then shortest first with any contained in another left out (MapLibre's order).
 */
export function attributionsOf(style: StyleLike, zoom: number): string[] {
  const used = new Set<string>();
  for (const l of style.layers ?? []) {
    const layer = l as Record<string, unknown>;
    if (typeof layer.source === "string" && shown(layer, zoom)) used.add(layer.source);
  }
  const terrain = (style.terrain as { source?: unknown } | undefined)?.source;
  if (typeof terrain === "string") used.add(terrain);
  let out: string[] = [];
  for (const [id, s] of Object.entries(style.sources ?? {})) {
    const a = (s as { attribution?: unknown })?.attribution;
    if (used.has(id) && typeof a === "string" && !out.includes(a)) out.push(a);
  }
  out = out.filter((a) => a.trim());
  out.sort((a, b) => a.length - b.length);
  return out.filter((a, i) => !out.slice(i + 1).some((b) => b.includes(a)));
}
