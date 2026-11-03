// The search box without its look: the query, results from every provider
// (searched after a pause in typing, earlier searches aborted), the active
// result for keyboard and ARIA, and the map moved to the chosen one.
import type { Map } from "../index";
import { Store, type Controller } from "../ui/controller";
import type { LngLat, SearchProvider, SearchRequest, SearchResult } from "./types";

/**
 * `query` as typed; `results` from the providers in their order; `active` the one the arrow keys
 * reached (-1: none); `open` while there are results to choose from; `loading`; `errors` of providers
 * that failed this time (the others' results still show); `selected` the last one chosen.
 */
export interface SearchState {
  query: string;
  results: SearchResult[];
  active: number;
  open: boolean;
  loading: boolean;
  errors: { provider: string; message: string }[];
  selected: SearchResult | null;
}

/**
 * `providers` in the order their results show; `debounce` ms of quiet typing before searching
 * (default 250); `limit` results per provider (default 8); `zoom` for a point chosen (default 16) and
 * `maxZoom` for an area (default 17).
 */
export interface SearchOptions {
  providers: SearchProvider[];
  debounce?: number;
  limit?: number;
  zoom?: number;
  maxZoom?: number;
}

export interface Search extends Controller<SearchState> {
  setQuery(query: string): void;
  /** Searches now (on Enter, say), not after the pause. */
  submit(): Promise<void>;
  /** Moves the active result by `delta`, wrapping around. */
  move(delta: number): void;
  /** Chooses result `index` (default the active one, else the first) and moves the map to it. */
  select(index?: number): void;
  close(): void;
  clear(): void;
  /** What the providers with `reverse` say is at `lngLat`. */
  reverse(lngLat: LngLat): Promise<SearchResult[]>;
}

/** The longest query the providers get: longer text is cut (patterns stay quick, web APIs get a sane URL). */
export const MAX_QUERY_LENGTH = 256;

class SearchStore extends Store<SearchState> implements Search {
  #map: Map;
  #options: SearchOptions;
  #timer: ReturnType<typeof setTimeout> | undefined;
  #abort: AbortController | null = null;

  constructor(map: Map, options: SearchOptions) {
    super({ query: "", results: [], active: -1, open: false, loading: false, errors: [], selected: null });
    this.#map = map;
    this.#options = options;
    this.onDestroy(() => this.#cancel());
  }

  #cancel(): void {
    clearTimeout(this.#timer);
    this.#abort?.abort();
    this.#abort = null;
  }

  #request(signal: AbortSignal): SearchRequest {
    const b = this.#map.getBounds();
    return { signal, bbox: Number.isFinite(b.west) ? [b.west, b.south, b.east, b.north] : null, limit: this.#options.limit ?? 8 };
  }

  setQuery(query: string): void {
    this.#cancel();
    if (!query.trim()) {
      this.set({ query, results: [], active: -1, open: false, loading: false, errors: [] });
      return;
    }
    this.set({ query, loading: true });
    this.#timer = setTimeout(() => void this.submit(), this.#options.debounce ?? 250);
  }

  async submit(): Promise<void> {
    this.#cancel();
    const query = this.state.query.slice(0, MAX_QUERY_LENGTH);
    if (!query.trim()) return;
    const abort = (this.#abort = new AbortController());
    this.set({ loading: true });
    const request = this.#request(abort.signal);
    const settled = await Promise.allSettled(this.#options.providers.map(async (p) => p.search(query, request)));
    // The query changed while the providers answered: their results are stale.
    if (abort.signal.aborted) return;
    const results: SearchResult[] = [];
    const errors: SearchState["errors"] = [];
    settled.forEach((s, i) => {
      if (s.status === "fulfilled") results.push(...s.value);
      else errors.push({ provider: this.#options.providers[i].name, message: String((s.reason as Error)?.message ?? s.reason) });
    });
    this.#abort = null;
    this.set({ results, errors, active: -1, open: results.length > 0, loading: false });
  }

  move(delta: number): void {
    const n = this.state.results.length;
    if (n === 0) return;
    const from = this.state.active < 0 ? (delta > 0 ? -1 : 0) : this.state.active;
    this.set({ active: (((from + delta) % n) + n) % n, open: true });
  }

  select(index = this.state.active < 0 ? 0 : this.state.active): void {
    const r = this.state.results[index];
    if (!r) return;
    if (r.bbox) this.#map.fitBounds(r.bbox, { maxZoom: this.#options.maxZoom ?? 17, padding: 40 });
    else this.#map.flyTo({ center: r.lngLat, zoom: this.#options.zoom ?? 16 });
    this.set({ selected: r, active: index, open: false });
  }

  close(): void {
    this.set({ open: false, active: -1 });
  }

  clear(): void {
    this.#cancel();
    this.set({ query: "", results: [], active: -1, open: false, loading: false, errors: [], selected: null });
  }

  async reverse(lngLat: LngLat): Promise<SearchResult[]> {
    const request = this.#request(new AbortController().signal);
    const settled = await Promise.allSettled(this.#options.providers.filter((p) => p.reverse).map(async (p) => p.reverse!(lngLat, request)));
    return settled.flatMap((s) => (s.status === "fulfilled" ? s.value : []));
  }
}

export function createSearch(map: Map, options: SearchOptions): Search {
  return new SearchStore(map, options);
}
