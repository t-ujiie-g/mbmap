// A basemap swap that keeps the overlays: the `transformStyle` of
// `mbmap/ui`'s basemap controller. Import-free.

interface Layer {
  id: string;
  source?: unknown;
  metadata?: unknown;
}

interface Style {
  sources?: Record<string, unknown>;
  layers: unknown[];
}

/** The `metadata` key that marks a layer as an overlay, kept when the basemap changes. */
export const OVERLAY = "mbmap:overlay";

/** Whether a layer is an overlay by default: its `metadata` says `"mbmap:overlay": true`. */
export function isOverlay(layer: Layer): boolean {
  return (layer.metadata as Record<string, unknown> | undefined)?.[OVERLAY] === true;
}

/** What `addOverlay` needs of a map. */
interface LayerHost {
  getSource(id: string): unknown;
  addSource(id: string, source: unknown): unknown;
  addLayer(layer: any): unknown;
  removeLayer(id: string): unknown;
  removeSource(id: string): unknown;
}

/**
 * Empty GeoJSON sources `sources` and `layers` over them, marked as overlays, unless the first
 * source is there already; returns what removes them (once).
 */
export function addOverlay(map: LayerHost, sources: string[], layers: { id: string; [key: string]: unknown }[]): () => void {
  if (!map.getSource(sources[0])) {
    for (const id of sources) map.addSource(id, { type: "geojson", data: { type: "FeatureCollection", features: [] } });
    for (const l of layers) map.addLayer({ ...l, metadata: { [OVERLAY]: true } });
  }
  let removed = false;
  return () => {
    if (removed || !map.getSource(sources[0])) return;
    removed = true;
    for (const l of [...layers].reverse()) map.removeLayer(l.id);
    for (const id of sources) map.removeSource(id);
  };
}

/**
 * `next` with the overlays of `previous` kept as they are: in its place where `next` has a layer of
 * the same id, else on top, in their order, with their sources.
 */
export function withOverlays<S extends Style>(previous: S | undefined, next: S, overlay: (layer: Layer) => boolean = isOverlay): S {
  const kept = ((previous?.layers ?? []) as Layer[]).filter(overlay);
  if (kept.length === 0) return next;
  const byId = new Map(kept.map((l) => [l.id, l]));
  const sources = { ...next.sources };
  for (const l of kept) {
    if (typeof l.source === "string" && previous?.sources?.[l.source]) sources[l.source] = previous.sources[l.source];
  }
  const layers = (next.layers as Layer[]).map((l) => byId.get(l.id) ?? l);
  const placed = new Set(layers.map((l) => l.id));
  layers.push(...kept.filter((l) => !placed.has(l.id)));
  return { ...next, sources, layers };
}
