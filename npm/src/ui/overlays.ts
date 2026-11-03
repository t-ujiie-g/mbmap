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

/** Whether a layer is an overlay by default: its `metadata` says `"mbmap:overlay": true`. */
export function isOverlay(layer: Layer): boolean {
  return (layer.metadata as Record<string, unknown> | undefined)?.["mbmap:overlay"] === true;
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
