// The attribute table's rows without the map: features to rows, columns,
// sorting, filtering and paging. Imports only the search's folding.
import { type Geometry, normalize } from "../search/dataset.ts";

/**
 * A feature as a row: its `id` (null without one), `properties` and `geometry` (a GeometryCollection
 * of the pieces when several tiles held parts of it).
 */
export interface TableRow {
  id: string | number | null;
  properties: Record<string, unknown>;
  geometry: Geometry | null;
}

interface Feature {
  id?: unknown;
  properties?: Record<string, unknown> | null;
  geometry?: Geometry | null;
}

/** The features of GeoJSON `data`: a FeatureCollection's, or the Feature itself. */
export function featuresOf(data: unknown): Feature[] {
  return (data as { features?: Feature[] } | null)?.features ?? (data ? [data as Feature] : []);
}

/**
 * Rows of `features`, one per id (the property `idKey` names, or the feature's id): pieces of one
 * feature from several tiles become one row; features without an id stay apart.
 */
export function rowsOf(features: readonly Feature[], idKey?: string): TableRow[] {
  const rows: TableRow[] = [];
  const byId = new Map<string, TableRow>();
  for (const f of features) {
    const properties = { ...f.properties };
    const id = ((idKey === undefined ? f.id : properties[idKey]) ?? null) as string | number | null;
    const geometry = f.geometry ?? null;
    const seen = id === null ? undefined : byId.get(String(id));
    if (seen) {
      seen.geometry = { type: "GeometryCollection", geometries: [seen.geometry, geometry] };
      continue;
    }
    const row = { id, properties, geometry };
    if (id !== null) byId.set(String(id), row);
    rows.push(row);
  }
  return rows;
}

/** The property keys of `rows`, in the order they are first seen. */
export function columnsOf(rows: readonly TableRow[]): string[] {
  const keys = new Set<string>();
  for (const r of rows) for (const k of Object.keys(r.properties)) keys.add(k);
  return [...keys];
}

/** A cell as text: "" for null and undefined, JSON for objects and arrays. */
export function cellText(v: unknown): string {
  if (v === null || v === undefined) return "";
  return typeof v === "object" ? JSON.stringify(v) : String(v);
}

/** 0 for numbers, 1 for other values, 2 for missing ones (null, undefined). */
const rank = (v: unknown) => (v == null ? 2 : typeof v === "number" ? 0 : 1);

/**
 * `rows` sorted by `column` (a copy; ties keep their order): numbers by value, then other values as
 * text by `collator`, then missing values, in either direction.
 */
export function sortRows(rows: readonly TableRow[], column: string, direction: "asc" | "desc", collator: Intl.Collator): TableRow[] {
  const sign = direction === "desc" ? -1 : 1;
  return [...rows].sort((a, b) => {
    const x = a.properties[column];
    const y = b.properties[column];
    const rx = rank(x);
    const ry = rank(y);
    if (rx !== ry) return rx - ry;
    if (rx === 2) return 0;
    return sign * (rx === 0 ? (x as number) - (y as number) : collator.compare(cellText(x), cellText(y)));
  });
}

/**
 * The rows whose `columns` contain `query` (full and half width, case and kana folded, as the
 * search's dataset provider compares) and that pass `predicate`; an empty query passes every row.
 */
export function filterRows(rows: readonly TableRow[], query: string, columns: readonly string[], predicate?: ((row: TableRow) => boolean) | null): TableRow[] {
  const q = normalize(query);
  return rows.filter((r) => (!q || columns.some((c) => normalize(cellText(r.properties[c])).includes(q))) && (!predicate || predicate(r)));
}

/** Page `page` clamped to the `pages` that `count` rows make at `size` per page (at least one). */
export function pageOf(count: number, page: number, size: number): { page: number; pages: number } {
  const pages = Math.max(1, Math.ceil(count / size));
  return { page: Math.max(0, Math.min(pages - 1, Math.floor(page) || 0)), pages };
}
