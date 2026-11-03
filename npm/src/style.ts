// Edits of a style document as `addLayer`, `setPaintProperty` and the like make
// them: each returns a new document or throws an Error naming what is wrong.
// Import-free, so that `npm test` can load it.

/** A MapLibre style document; anything mbmap cannot draw faithfully is an error. */
export interface StyleSpecification {
  version: 8;
  sources: Record<string, unknown>;
  layers: unknown[];
  [key: string]: unknown;
}

/** A style layer as MapLibre's `LayerSpecification`; `paint` and `layout` hold its properties by name. */
export interface LayerSpecification {
  id: string;
  type: string;
  source?: string;
  "source-layer"?: string;
  minzoom?: number;
  maxzoom?: number;
  filter?: unknown;
  layout?: Record<string, unknown>;
  paint?: Record<string, unknown>;
  [key: string]: unknown;
}

function layers(style: StyleSpecification): LayerSpecification[] {
  return style.layers as LayerSpecification[];
}

function indexOf(style: StyleSpecification, id: string): number {
  const i = layers(style).findIndex((l) => l.id === id);
  if (i < 0) throw new Error(`mbmap: the style has no layer "${id}"`);
  return i;
}

/** A plain copy, so that later changes by the caller do not reach the map. */
export function copy<T>(value: T): T {
  return value === undefined ? value : (JSON.parse(JSON.stringify(value)) as T);
}

export function getLayer(style: StyleSpecification, id: string): LayerSpecification | undefined {
  return layers(style).find((l) => l.id === id);
}

function withLayer(style: StyleSpecification, id: string, f: (l: LayerSpecification) => LayerSpecification): StyleSpecification {
  const i = indexOf(style, id);
  const next = [...layers(style)];
  next[i] = f(next[i]);
  return { ...style, layers: next };
}

/** Adds `layer` before the layer `beforeId` names, or on top. */
export function addLayer(style: StyleSpecification, layer: LayerSpecification, beforeId?: string): StyleSpecification {
  if (typeof layer?.id !== "string" || typeof layer.type !== "string") throw new Error("mbmap: a layer needs an id and a type");
  if (getLayer(style, layer.id)) throw new Error(`mbmap: the style already has a layer "${layer.id}"`);
  if (layer.type !== "background" && !(typeof layer.source === "string" && layer.source in style.sources)) {
    throw new Error(`mbmap: layer "${layer.id}": the style has no source "${String(layer.source)}"`);
  }
  const next = [...layers(style)];
  next.splice(beforeId === undefined ? next.length : indexOf(style, beforeId), 0, copy(layer));
  return { ...style, layers: next };
}

export function removeLayer(style: StyleSpecification, id: string): StyleSpecification {
  const i = indexOf(style, id);
  return { ...style, layers: layers(style).filter((_, k) => k !== i) };
}

/** Moves layer `id` before the layer `beforeId` names, or on top. */
export function moveLayer(style: StyleSpecification, id: string, beforeId?: string): StyleSpecification {
  const layer = layers(style)[indexOf(style, id)];
  if (beforeId !== undefined) indexOf(style, beforeId);
  const rest = layers(style).filter((l) => l.id !== id);
  const at = beforeId === undefined ? rest.length : rest.findIndex((l) => l.id === beforeId);
  rest.splice(at < 0 ? rest.length : at, 0, layer);
  return { ...style, layers: rest };
}

function setProperty(style: StyleSpecification, id: string, group: "paint" | "layout", name: string, value: unknown): StyleSpecification {
  return withLayer(style, id, (l) => {
    const props = { ...l[group] };
    if (value === undefined || value === null) delete props[name];
    else props[name] = copy(value);
    return { ...l, [group]: props };
  });
}

/** Sets paint property `name` of layer `id`; undefined or null goes back to its default. */
export function setPaintProperty(style: StyleSpecification, id: string, name: string, value: unknown): StyleSpecification {
  return setProperty(style, id, "paint", name, value);
}

export function setLayoutProperty(style: StyleSpecification, id: string, name: string, value: unknown): StyleSpecification {
  return setProperty(style, id, "layout", name, value);
}

export function getPaintProperty(style: StyleSpecification, id: string, name: string): unknown {
  return copy(getLayer(style, id)?.paint?.[name]);
}

export function getLayoutProperty(style: StyleSpecification, id: string, name: string): unknown {
  return copy(getLayer(style, id)?.layout?.[name]);
}

/** Sets the filter of layer `id`; undefined or null removes it. */
export function setFilter(style: StyleSpecification, id: string, filter: unknown): StyleSpecification {
  return withLayer(style, id, (l) => {
    const { filter: _, ...rest } = l;
    return filter === undefined || filter === null ? (rest as LayerSpecification) : { ...rest, filter: copy(filter) };
  });
}

export function getFilter(style: StyleSpecification, id: string): unknown {
  return copy(getLayer(style, id)?.filter);
}

/** Shows layer `id` only from zoom `minzoom` up to `maxzoom`. */
export function setLayerZoomRange(style: StyleSpecification, id: string, minzoom: number, maxzoom: number): StyleSpecification {
  if (!(minzoom >= 0 && maxzoom <= 24 && minzoom <= maxzoom)) throw new RangeError("mbmap: a layer's zoom range must lie in 0-24, min not above max");
  return withLayer(style, id, (l) => ({ ...l, minzoom, maxzoom }));
}

export function addSource(style: StyleSpecification, id: string, source: unknown): StyleSpecification {
  if (id in style.sources) throw new Error(`mbmap: the style already has a source "${id}"`);
  if (typeof (source as { type?: unknown })?.type !== "string") throw new Error(`mbmap: source "${id}" needs a type`);
  return { ...style, sources: { ...style.sources, [id]: copy(source) } };
}

/** Removes source `id`; throws while a layer or the terrain uses it, as MapLibre refuses to. */
export function removeSource(style: StyleSpecification, id: string): StyleSpecification {
  if (!(id in style.sources)) throw new Error(`mbmap: the style has no source "${id}"`);
  const user = layers(style).find((l) => l.source === id);
  if (user) throw new Error(`mbmap: source "${id}" is used by layer "${user.id}"`);
  if ((style.terrain as { source?: unknown } | undefined)?.source === id) throw new Error(`mbmap: source "${id}" is used by the terrain`);
  const { [id]: _, ...sources } = style.sources;
  return { ...style, sources };
}

/** Replaces the GeoJSON `data` of source `id`. */
export function setSourceData(style: StyleSpecification, id: string, data: unknown): StyleSpecification {
  const source = style.sources[id] as { type?: unknown } | undefined;
  if (source?.type !== "geojson") throw new Error(`mbmap: source "${id}" is not a GeoJSON source`);
  return { ...style, sources: { ...style.sources, [id]: { ...source, data: copy(data) } } };
}

/**
 * `next` with the GeoJSON `data` of `previous` wherever the two are written alike, so that
 * the sources they share keep their tiles: a source's data is compared by identity after this.
 */
export function keepGeoJSONData(previous: StyleSpecification | null, next: StyleSpecification): StyleSpecification {
  if (!previous) return next;
  const sources = { ...next.sources };
  for (const [id, s] of Object.entries(sources)) {
    const src = s as { type?: unknown; data?: unknown };
    const old = previous.sources[id] as { type?: unknown; data?: unknown } | undefined;
    if (src?.type === "geojson" && old?.type === "geojson" && old.data !== src.data && JSON.stringify(old.data) === JSON.stringify(src.data)) {
      sources[id] = { ...src, data: old.data };
    }
  }
  return { ...next, sources };
}

/**
 * Whether `f` may be a legacy filter, which `legacy.ts` converts: MapLibre's `classifyFilter`,
 * except that `all` and `any` mixing legacy filters with expressions count (the converter keeps them).
 */
export function isLegacyFilter(f: unknown): boolean {
  if (typeof f === "boolean" || f === undefined) return false;
  if (!Array.isArray(f) || f.length === 0) return true;
  switch (f[0]) {
    case "has":
      return f.length < 2 || f[1] === "$id" || f[1] === "$type";
    case "in":
      return !(f.length >= 3 && (typeof f[1] !== "string" || Array.isArray(f[2])));
    case "!in":
    case "!has":
    case "none":
      return true;
    case "==":
    case "!=":
    case ">":
    case ">=":
    case "<":
    case "<=":
      return f.length === 3 && !Array.isArray(f[1]) && !Array.isArray(f[2]);
    case "any":
    case "all":
      return f.slice(1).some(isLegacyFilter);
    default:
      return false;
  }
}

/** Whether a layer of `style` may have a legacy filter or a property function (a plain object as a paint or layout value). */
export function hasLegacy(style: StyleSpecification): boolean {
  const fn = (o: unknown) => !!o && Object.values(o).some((v) => typeof v === "object" && v !== null && !Array.isArray(v));
  return layers(style).some((l) => isLegacyFilter(l.filter) || fn(l.paint) || fn(l.layout));
}

/** Sets a top-level property such as `terrain`, `sky` or `light`; undefined or null removes it. */
export function setRoot(style: StyleSpecification, key: "terrain" | "sky" | "light", value: unknown): StyleSpecification {
  const { [key]: _, ...rest } = style;
  return (value === undefined || value === null ? rest : { ...rest, [key]: copy(value) }) as StyleSpecification;
}
