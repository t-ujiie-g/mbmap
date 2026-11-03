// The shapes searches and providers share (VISION §6).

export interface LngLat {
  lng: number;
  lat: number;
}

/** One result: what to show (`label`, `detail`), where it is (`lngLat`, and `bbox` west, south, east, north for an area). */
export interface SearchResult {
  provider: string;
  label: string;
  detail?: string;
  lngLat: LngLat;
  bbox?: [number, number, number, number];
  properties?: Record<string, unknown>;
}

/** What a provider is asked with: `signal` aborts a search the query has moved on from; `bbox` is the view. */
export interface SearchRequest {
  signal: AbortSignal;
  bbox: [number, number, number, number] | null;
  limit: number;
}

/** A provider (VISION §6): `search`, and optionally `reverse` (what is at a place). External APIs fit this shape. */
export interface SearchProvider {
  name: string;
  search(query: string, request: SearchRequest): SearchResult[] | Promise<SearchResult[]>;
  reverse?(lngLat: LngLat, request: SearchRequest): SearchResult[] | Promise<SearchResult[]>;
}

/** Coordinates from one CRS to another, as mbmap/analysis's `transform`. */
export type Transform = (coords: ArrayLike<number>, from: number | string, to: number | string) => Promise<ArrayLike<number>>;
