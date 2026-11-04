// The dataset provider: loaded GeoJSON features found by their properties,
// compared as NFKC, lower case and hiragana. Import-free (types aside).
import type { SearchProvider, SearchResult } from "./types";

/** `s` in the form search compares. */
export function normalize(s: string): string {
  return s
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60))
    .replace(/\s+/g, " ")
    .trim();
}

/** How well `text` matches `query` (both normalized): 3 equal, 2 prefix, 1 contains, 0 not at all. */
export function matchRank(text: string, query: string): number {
  if (!query) return 0;
  if (text === query) return 3;
  if (text.startsWith(query)) return 2;
  return text.includes(query) ? 1 : 0;
}

/** A GeoJSON geometry, or a GeometryCollection of them. */
export interface Geometry {
  type: string;
  coordinates?: unknown;
  geometries?: (Geometry | null)[];
}

interface Feature {
  properties?: Record<string, unknown> | null;
  geometry?: Geometry | null;
}

/** The bounding box of a GeoJSON geometry's coordinates (collections' included, nested too), or null without any. */
export function boxOf(g: Geometry | null | undefined): [number, number, number, number] | null {
  const box: [number, number, number, number] = [Infinity, Infinity, -Infinity, -Infinity];
  const walk = (c: unknown): void => {
    if (!Array.isArray(c)) return;
    if (typeof c[0] === "number" && typeof c[1] === "number") {
      box[0] = Math.min(box[0], c[0]);
      box[1] = Math.min(box[1], c[1]);
      box[2] = Math.max(box[2], c[0]);
      box[3] = Math.max(box[3], c[1]);
    } else c.forEach(walk);
  };
  const geometry = (x: Geometry | null | undefined): void => {
    walk(x?.coordinates);
    x?.geometries?.forEach(geometry);
  };
  geometry(g);
  return Number.isFinite(box[0]) ? box : null;
}

/**
 * The features of `data` (a GeoJSON FeatureCollection, or a function giving the current one) whose
 * `fields` contain the query (full and half width, case and kana folded): equal first, then those
 * starting with it, then the rest. `label(feature)` names a result (default its first field).
 */
export function datasetSearch(
  data: { features: Feature[] } | (() => { features: Feature[] }),
  options: { fields: string[]; label?: (f: Feature) => string; name?: string },
): SearchProvider {
  const name = options.name ?? "dataset";
  let indexed: { features: Feature[] } | null = null;
  let texts: string[][] = [];
  return {
    name,
    search(query, { limit }) {
      const current = typeof data === "function" ? data() : data;
      if (current !== indexed) {
        indexed = current;
        texts = current.features.map((f) => options.fields.map((k) => normalize(String(f.properties?.[k] ?? ""))));
      }
      const q = normalize(query);
      const hits: { f: Feature; rank: number }[] = [];
      current.features.forEach((f, i) => {
        const rank = Math.max(0, ...texts[i].map((t) => matchRank(t, q)));
        if (rank > 0) hits.push({ f, rank });
      });
      hits.sort((a, b) => b.rank - a.rank);
      const out: SearchResult[] = [];
      for (const { f } of hits) {
        const box = boxOf(f.geometry);
        if (!box) continue;
        const point = box[0] === box[2] && box[1] === box[3];
        out.push({
          provider: name,
          label: options.label?.(f) ?? String(f.properties?.[options.fields[0]] ?? ""),
          lngLat: { lng: (box[0] + box[2]) / 2, lat: (box[1] + box[3]) / 2 },
          bbox: point ? undefined : box,
          properties: f.properties ?? {},
        });
        if (out.length >= limit) break;
      }
      return out;
    },
  };
}
