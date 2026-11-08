// The field editor's operations without the map: columns of GeoJSON features set, removed
// and renamed in place. Import-free, for `npm test`.

interface Feature {
  properties?: Record<string, unknown> | null;
}

/** Throws unless `name` can be a property key: a non-empty string other than `__proto__`. */
export function checkColumn(name: unknown): string {
  if (typeof name !== "string" || name === "" || name === "__proto__") throw new Error(`mbmap: field editor: invalid column ${JSON.stringify(name)}`);
  return name;
}

/** Sets `column` of `features[indices[k]]` to `values[k]` (a feature without properties gets them). */
export function setColumn(features: Feature[], column: string, indices: readonly number[], values: readonly unknown[]): void {
  checkColumn(column);
  indices.forEach((i, k) => {
    const f = features[i];
    f.properties = { ...f.properties, [column]: values[k] ?? null };
  });
}

/** Removes `column` from every feature. */
export function removeColumn(features: Feature[], column: string): void {
  for (const f of features) {
    if (f.properties && Object.hasOwn(f.properties, column)) {
      const { [column]: _, ...rest } = f.properties;
      f.properties = rest;
    }
  }
}

/** Renames `from` to `to` in every feature, where it stood among the keys; throws when a feature already has `to`. */
export function renameColumn(features: Feature[], from: string, to: string): void {
  checkColumn(to);
  if (from === to) return;
  if (features.some((f) => f.properties && Object.hasOwn(f.properties, to))) throw new Error(`mbmap: field editor: column ${JSON.stringify(to)} exists`);
  for (const f of features) {
    const p = f.properties;
    if (!p || !Object.hasOwn(p, from)) continue;
    f.properties = Object.fromEntries(Object.keys(p).map((k) => [k === from ? to : k, p[k]]));
  }
}

interface Identified extends Feature {
  id?: unknown;
}

/**
 * The `updateData` diff that gives `features[i]` its properties for each `i` in `changed`, ids taken
 * as MapLibre's `toUpdateable` takes them (`promoteId`'s property, else the feature's id); undefined
 * when a feature lacks an id, two share one, or `before` (the ids before the edit) differs.
 */
export function propertiesDiff(features: Identified[], changed: readonly number[], before: readonly unknown[], promoteId?: string) {
  const ids = idsOf(features, promoteId);
  if (!ids || ids.some((id, i) => !Object.is(id, before[i]))) return undefined;
  return {
    update: changed.map((i) => ({
      id: ids[i] as string | number,
      removeAllProperties: true,
      addOrUpdateProperties: Object.entries(features[i].properties ?? {}).map(([key, value]) => ({ key, value })),
    })),
  };
}

/** Each feature's id (`promoteId`'s property, else its id), or undefined when one is missing or repeated. */
export function idsOf(features: Identified[], promoteId?: string): unknown[] | undefined {
  const ids = features.map((f) => (promoteId ? f.properties?.[promoteId] : f.id));
  return ids.some((id) => id == null) || new Set(ids).size < ids.length ? undefined : ids;
}
