// The attribute table's field operations without the map: columns of GeoJSON features set, removed
// and renamed in place. Import-free, for `npm test`.

interface Feature {
  properties?: Record<string, unknown> | null;
}

/** Throws unless `name` can be a property key: a non-empty string other than `__proto__`. */
export function checkColumn(name: unknown): string {
  if (typeof name !== "string" || name === "" || name === "__proto__") throw new Error(`mbmap: attribute table: invalid column ${JSON.stringify(name)}`);
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
  if (features.some((f) => f.properties && Object.hasOwn(f.properties, to))) throw new Error(`mbmap: attribute table: column ${JSON.stringify(to)} exists`);
  for (const f of features) {
    const p = f.properties;
    if (!p || !Object.hasOwn(p, from)) continue;
    f.properties = Object.fromEntries(Object.keys(p).map((k) => [k === from ? to : k, p[k]]));
  }
}
