// A port of MapLibre 6.16's src/source/geojson_source_diff.ts (BSD-3-Clause, NOTICE) and of the
// bounds its GeoJSONSource reloads tiles by. Import-free, so that `npm test` can load it.

export type GeoJSONFeatureId = number | string;

/** One feature's change, applied in this order: `newGeometry`, `removeAllProperties`, `removeProperties`, `addOrUpdateProperties`. */
export interface GeoJSONFeatureDiff {
  id: GeoJSONFeatureId;
  newGeometry?: unknown;
  removeAllProperties?: boolean;
  removeProperties?: string[];
  addOrUpdateProperties?: { key: string; value: unknown }[];
}

/** MapLibre's `GeoJSONSourceDiff`, applied in this order: `removeAll` or `remove`, `add`, `update`. */
export interface GeoJSONSourceDiff {
  removeAll?: boolean;
  remove?: GeoJSONFeatureId[];
  add?: Feature[];
  update?: GeoJSONFeatureDiff[];
}

export interface Feature {
  type?: unknown;
  id?: unknown;
  properties?: Record<string, unknown> | null;
  geometry?: unknown;
}

export type Updateable = Map<unknown, Feature>;

/** Whether `diff` has MapLibre's shape: `remove`, `add` and `update` absent or arrays, features and updates objects. */
export function isSourceDiff(diff: unknown): diff is GeoJSONSourceDiff {
  if (typeof diff !== "object" || diff === null) return false;
  const d = diff as Record<string, unknown>;
  const objects = (v: unknown) => v === undefined || (Array.isArray(v) && v.every((x) => typeof x === "object" && x !== null));
  return (d.remove === undefined || Array.isArray(d.remove)) && objects(d.add) && objects(d.update);
}

const featureId = (f: Feature, promoteId: string | undefined): unknown => (promoteId ? f.properties?.[promoteId] : f.id);

/**
 * The features of `data` by id (MapLibre's `toUpdateable`): null and `{}` give none, a Feature or a
 * FeatureCollection gives its features when each has an id of its own; otherwise undefined.
 */
export function toUpdateable(data: unknown, promoteId?: string): Updateable | undefined {
  const updateable: Updateable = new Map();
  if (data == null) return updateable;
  const d = data as { type?: unknown; features?: unknown };
  if (d.type == null) return updateable;
  if (d.type === "Feature") {
    const id = featureId(d as Feature, promoteId);
    if (id == null) return undefined;
    updateable.set(id, d as Feature);
    return updateable;
  }
  if (d.type !== "FeatureCollection" || !Array.isArray(d.features)) return undefined;
  for (const f of d.features as Feature[]) {
    const id = featureId(f, promoteId);
    if (id == null || updateable.has(id)) return undefined;
    updateable.set(id, f);
  }
  return updateable;
}

// A plain assignment of `__proto__` would set the object's prototype instead.
function setProperty(properties: Record<string, unknown>, key: string, value: unknown): void {
  Object.defineProperty(properties, key, { value, enumerable: true, writable: true, configurable: true });
}

/**
 * Applies `diff` to `updateable` as MapLibre's `applySourceDiff` does, a changed feature replaced by a
 * shallow copy, and returns the geometries it touched before and after (none for `removeAll`).
 */
export function applySourceDiff(updateable: Updateable, diff: GeoJSONSourceDiff, promoteId?: string): unknown[] {
  const affected: unknown[] = [];
  if (diff.removeAll) {
    updateable.clear();
  } else if (diff.remove) {
    for (const id of diff.remove) {
      const existing = updateable.get(id);
      if (!existing) continue;
      affected.push(existing.geometry);
      updateable.delete(id);
    }
  }
  for (const f of diff.add ?? []) {
    const id = featureId(f, promoteId);
    if (id == null) continue;
    const existing = updateable.get(id);
    if (existing) affected.push(existing.geometry);
    affected.push(f.geometry);
    updateable.set(id, f);
  }
  for (const u of diff.update ?? []) {
    const existing = updateable.get(u.id);
    if (!existing) continue;
    const changeGeometry = !!u.newGeometry;
    const changeProps = u.removeAllProperties || (u.removeProperties?.length ?? 0) > 0 || (u.addOrUpdateProperties?.length ?? 0) > 0;
    if (!changeGeometry && !changeProps) continue;
    affected.push(existing.geometry);
    const f = { ...existing };
    updateable.set(u.id, f);
    if (changeGeometry) {
      affected.push(u.newGeometry);
      f.geometry = u.newGeometry;
    }
    if (changeProps) {
      const properties: Record<string, unknown> = u.removeAllProperties ? {} : { ...(f.properties || {}) };
      f.properties = properties;
      for (const key of u.removeProperties ?? []) delete properties[key];
      for (const { key, value } of u.addOrUpdateProperties ?? []) setProperty(properties, key, value);
    }
  }
  return affected;
}

interface Hashed {
  removeAll?: boolean;
  remove: Set<unknown>;
  add: Map<unknown, Feature>;
  update: Map<unknown, GeoJSONFeatureDiff>;
}

const hashed = (d: GeoJSONSourceDiff, promoteId: string | undefined): Hashed => ({
  removeAll: d.removeAll,
  remove: new Set(d.remove ?? []),
  add: new Map(d.add?.map((f) => [featureId(f, promoteId), f])),
  update: new Map(d.update?.map((u) => [u.id, u])),
});

function mergeFeatureDiffs(prev: GeoJSONFeatureDiff, next: GeoJSONFeatureDiff): GeoJSONFeatureDiff {
  const merged: GeoJSONFeatureDiff = { id: prev.id };
  if (next.removeAllProperties) {
    delete prev.removeProperties;
    delete prev.addOrUpdateProperties;
    delete next.removeProperties;
  }
  if (next.removeProperties && prev.addOrUpdateProperties) {
    const removed = new Set(next.removeProperties);
    prev.addOrUpdateProperties = prev.addOrUpdateProperties.filter((p) => !removed.has(p.key));
  }
  if (prev.removeAllProperties || next.removeAllProperties) merged.removeAllProperties = true;
  if (prev.removeProperties || next.removeProperties) merged.removeProperties = [...(prev.removeProperties || []), ...(next.removeProperties || [])];
  if (prev.addOrUpdateProperties || next.addOrUpdateProperties) {
    merged.addOrUpdateProperties = [...(prev.addOrUpdateProperties || []), ...(next.addOrUpdateProperties || [])];
  }
  if (prev.newGeometry || next.newGeometry) merged.newGeometry = next.newGeometry || prev.newGeometry;
  return merged;
}

/** `prev` followed by `next` as one diff, as MapLibre's `mergeSourceDiffs` merges diffs waiting for its worker. */
export function mergeSourceDiffs(prevDiff: GeoJSONSourceDiff | undefined, nextDiff: GeoJSONSourceDiff | undefined, promoteId?: string): GeoJSONSourceDiff {
  if (!prevDiff) return nextDiff || {};
  if (!nextDiff) return prevDiff || {};
  const prev = hashed(prevDiff, promoteId);
  const next = hashed(nextDiff, promoteId);
  if (next.removeAll) {
    prev.add.clear();
    prev.update.clear();
    prev.remove.clear();
    next.remove.clear();
  }
  for (const id of next.remove) {
    prev.add.delete(id);
    prev.update.delete(id);
  }
  for (const id of next.add.keys()) prev.update.delete(id);
  for (const [id, u] of next.update) {
    const p = prev.update.get(id);
    if (!p) continue;
    next.update.set(id, mergeFeatureDiffs(p, u));
    prev.update.delete(id);
  }
  const remove = new Set([...prev.remove, ...next.remove]);
  const add = new Map([...prev.add, ...next.add]);
  if (remove.size && add.size) for (const id of add.keys()) remove.delete(id);
  const merged: GeoJSONSourceDiff = {};
  if (prev.removeAll || next.removeAll) merged.removeAll = true;
  merged.remove = [...remove] as GeoJSONFeatureId[];
  merged.add = [...add.values()];
  merged.update = [...new Map([...prev.update, ...next.update]).values()];
  return merged;
}

// Positions nested deeper than any geometry's (hostile input) are left out.
const MAX_DEPTH = 8;

function extend(box: number[], c: unknown, depth: number): void {
  if (!Array.isArray(c) || c.length === 0 || depth > MAX_DEPTH) return;
  if (typeof c[0] !== "number") {
    for (const p of c) extend(box, p, depth + 1);
    return;
  }
  const [lng, lat] = c as number[];
  if (!Number.isFinite(lng) || !Number.isFinite(lat)) return;
  box[0] = Math.min(box[0], lng);
  box[1] = Math.min(box[1], lat);
  box[2] = Math.max(box[2], lng);
  box[3] = Math.max(box[3], lat);
}

function extendGeometry(box: number[], g: unknown, depth: number): void {
  const geometry = g as { type?: unknown; geometries?: unknown; coordinates?: unknown } | null;
  if (!geometry || depth > MAX_DEPTH) return;
  if (geometry.type === "GeometryCollection") {
    if (Array.isArray(geometry.geometries)) for (const part of geometry.geometries) extendGeometry(box, part, depth + 1);
  } else {
    extend(box, geometry.coordinates, 0);
  }
}

// MapLibre's `wrap(lng, -180, 180)`, which turns -180 into 180.
function wrapLng(lng: number): number {
  const w = (((lng + 180) % 360) + 360) % 360 - 180;
  return w === -180 ? 180 : w;
}

// MapLibre's `LngLatBounds.intersects`, touching included.
function boxesMeet(a: number[], b: number[], i: number): boolean {
  if (!(b[i + 3] >= a[1] && b[i + 1] <= a[3])) return false;
  if (Math.abs(a[2] - a[0]) >= 360 || Math.abs(b[i + 2] - b[i]) >= 360) return true;
  const [w1, e1, w2, e2] = [wrapLng(a[0]), wrapLng(a[2]), wrapLng(b[i]), wrapLng(b[i + 2])];
  if (w1 > e1 && w2 > e2) return true;
  if (w1 > e1) return e2 >= w1 || w2 <= e1;
  if (w2 > e2) return e1 >= w2 || w1 <= e2;
  return w2 <= e1 && e2 >= w1;
}

const lngOf = (x: number) => x * 360 - 180;
const latOf = (y: number) => (360 / Math.PI) * Math.atan(Math.exp(((180 - y * 360) * Math.PI) / 180)) - 90;

/**
 * Whether tile z/x/y grown by `buffer` tiles meets one of `bounds` (west, south, east, north, ...):
 * MapLibre's `GeoJSONSource.shouldReloadTile` for a tile loaded, through `tileIdToLngLatBounds`.
 */
export function tileMeets(buffer: number, bounds: number[], z: number, x: number, y: number): boolean {
  const n = 2 ** z;
  const tile = [lngOf((x - buffer) / n), latOf((y + 1 + buffer) / n), lngOf((x + 1 + buffer) / n), latOf((y - buffer) / n)];
  for (let i = 0; i + 3 < bounds.length; i += 4) if (boxesMeet(tile, bounds, i)) return true;
  return false;
}

/**
 * The box of each geometry (MapLibre's `getGeoJSONBounds`), as west, south, east, north one after
 * another; geometries without a position are left out.
 */
export function geometryBounds(geometries: unknown[]): number[] {
  const out: number[] = [];
  for (const g of geometries) {
    const box = [Infinity, Infinity, -Infinity, -Infinity];
    extendGeometry(box, g, 0);
    if (box[0] <= box[2]) out.push(...box);
  }
  return out;
}
