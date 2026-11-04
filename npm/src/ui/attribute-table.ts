// An attribute table without its look: one source's features as rows to sort,
// filter, page through and select, the selection mirrored to the map.
import type { FitBoundsOptions, Map } from "../index";
import { Store, type Controller } from "./controller";
import { boxOf } from "../search/dataset";
import { columnsOf, featuresOf, filterRows, pageOf, rowsOf, sortRows, type TableRow } from "./table-rows";

export type { TableRow } from "./table-rows";

export type FeatureId = string | number;

/**
 * `columns` shown (the page's, or every property key in the order first seen); `rows` the current
 * page's, of `filtered` rows passing the query and filter out of `total`; `page` (from 0) of `pages`
 * at `pageSize`; `sort` (null for the source's order); `query`; `selected` ids (as strings, as
 * feature state keeps them); `loading` while the source is read; `error` if that failed.
 */
export interface AttributeTableState {
  columns: string[];
  rows: TableRow[];
  total: number;
  filtered: number;
  page: number;
  pages: number;
  pageSize: number;
  sort: { column: string; direction: "asc" | "desc" } | null;
  query: string;
  selected: string[];
  loading: boolean;
  error: Error | null;
}

/**
 * `source` (and `sourceLayer` for a vector source) to list: a GeoJSON source's data whole, a vector
 * source's features in the tiles drawn (one row per id); `columns` to show; `searchColumns` the query
 * looks in (default the columns); `filter` a predicate rows must pass; `pageSize` (default 50);
 * `locale` of the sort's collator (numeric); `highlight` the feature-state key set on selected
 * features (default `"selected"`, false for none); `fitBoundsOptions` for `zoomTo` (default padding
 * 40, maxZoom 17).
 */
export interface AttributeTableOptions {
  source: string;
  sourceLayer?: string;
  columns?: string[];
  searchColumns?: string[];
  filter?: ((row: TableRow) => boolean) | null;
  pageSize?: number;
  locale?: string | string[];
  highlight?: string | false;
  fitBoundsOptions?: FitBoundsOptions;
}

export interface AttributeTable extends Controller<AttributeTableState> {
  /** Reads the source again (done on its `sourcedata`, and on `idle` for a vector source). */
  refresh(): Promise<void>;
  /** Sorts by `column`; without a direction, ascending or the other way round on the same column; null for none. */
  setSort(column: string | null, direction?: "asc" | "desc"): void;
  setQuery(query: string): void;
  setFilter(filter: ((row: TableRow) => boolean) | null): void;
  setPageSize(size: number): void;
  goTo(page: number): void;
  next(): void;
  previous(): void;
  /** Selects the feature `id`, alone or with `add` added to the selection (or taken out if it was in). */
  select(id: FeatureId, options?: { add?: boolean }): void;
  clear(): void;
  /** Fits the map to feature `id`'s bounds; false when no row of that id has a geometry. */
  zoomTo(id: FeatureId, options?: FitBoundsOptions): boolean;
}

const atLeastOne = (n: number) => Math.max(1, Math.floor(n) || 1);

class AttributeTableStore extends Store<AttributeTableState> implements AttributeTable {
  #map: Map;
  #options: AttributeTableOptions;
  #collator: Intl.Collator;
  #filter: ((row: TableRow) => boolean) | null;
  #all: TableRow[] = [];
  #view: TableRow[] = [];
  #ticket = 0;
  #scheduled = false;

  constructor(map: Map, options: AttributeTableOptions) {
    const pageSize = atLeastOne(options.pageSize ?? 50);
    super({ columns: options.columns ?? [], rows: [], total: 0, filtered: 0, page: 0, pages: 1, pageSize, sort: null, query: "", selected: [], loading: false, error: null });
    this.#map = map;
    this.#options = options;
    this.#collator = new Intl.Collator(options.locale, { numeric: true });
    this.#filter = options.filter ?? null;
    const id = options.source;
    this.listen(map, "sourcedata", (e) => e.sourceId === id && this.#schedule());
    // Vector tiles come and go with the view; a source removed also ends up here.
    this.listen(map, "idle", () => map.getSource(id)?.type !== "geojson" && this.#schedule());
    this.onDestroy(() => this.clear());
    this.#schedule();
  }

  /** One refresh for the events of a task. */
  #schedule(): void {
    if (this.#scheduled) return;
    this.#scheduled = true;
    queueMicrotask(() => {
      this.#scheduled = false;
      void this.refresh();
    });
  }

  async refresh(): Promise<void> {
    const ticket = ++this.#ticket;
    const { source: id, sourceLayer } = this.#options;
    const source = this.#map.getSource(id);
    this.set({ loading: true });
    let rows: TableRow[];
    try {
      const geojson = source?.getData;
      // Vector features come with their promoted ids.
      rows = rowsOf(geojson ? featuresOf(await geojson()) : source ? await this.#map.querySourceFeatures(id, { sourceLayer }) : [], geojson && (source!.promoteId as string));
    } catch (err) {
      if (ticket === this.#ticket) this.set({ loading: false, error: err as Error });
      return;
    }
    // A later refresh has replaced this one.
    if (ticket !== this.#ticket) return;
    this.#all = rows;
    this.#update(true, { loading: false, error: null });
  }

  /** The state for the current rows (filtered and sorted again if `again`), with `patch`. */
  #update(again: boolean, patch: Partial<AttributeTableState> = {}): void {
    const s = { ...this.state, ...patch };
    if (again) {
      const columns = this.#options.columns ?? columnsOf(this.#all);
      const view = filterRows(this.#all, s.query, this.#options.searchColumns ?? columns, this.#filter);
      this.#view = s.sort ? sortRows(view, s.sort.column, s.sort.direction, this.#collator) : view;
      s.columns = columns;
    }
    const { page, pages } = pageOf(this.#view.length, s.page, s.pageSize);
    this.set({ ...s, total: this.#all.length, filtered: this.#view.length, page, pages, rows: this.#view.slice(page * s.pageSize, (page + 1) * s.pageSize) });
  }

  setSort(column: string | null, direction?: "asc" | "desc"): void {
    const now = this.state.sort;
    const d = direction ?? (now?.column === column && now.direction === "asc" ? "desc" : "asc");
    this.#update(true, { sort: column === null ? null : { column, direction: d } });
  }

  setQuery(query: string): void {
    if (query !== this.state.query) this.#update(true, { query, page: 0 });
  }

  setFilter(filter: ((row: TableRow) => boolean) | null): void {
    this.#filter = filter;
    this.#update(true, { page: 0 });
  }

  setPageSize(size: number): void {
    this.#update(false, { pageSize: atLeastOne(size), page: 0 });
  }

  goTo(page: number): void {
    this.#update(false, { page });
  }

  next(): void {
    this.goTo(this.state.page + 1);
  }

  previous(): void {
    this.goTo(this.state.page - 1);
  }

  select(id: FeatureId, options: { add?: boolean } = {}): void {
    const now = this.state.selected;
    const s = String(id);
    this.#select(!options.add ? [s] : now.includes(s) ? now.filter((x) => x !== s) : [...now, s]);
  }

  clear(): void {
    this.#select([]);
  }

  zoomTo(id: FeatureId, options: FitBoundsOptions = {}): boolean {
    const box = boxOf(this.#all.find((r) => r.id !== null && String(r.id) === String(id))?.geometry);
    if (!box) return false;
    this.#map.fitBounds(box, { padding: 40, maxZoom: 17, ...this.#options.fitBoundsOptions, ...options });
    return true;
  }

  /** Selects `next`, moving the highlight from the features selected before to those of `next`. */
  #select(next: string[]): void {
    const key = this.#options.highlight ?? "selected";
    const { source, sourceLayer } = this.#options;
    if (key !== false) {
      for (const id of this.state.selected) this.#map.setFeatureState({ source, sourceLayer, id }, { [key]: false });
      for (const id of next) this.#map.setFeatureState({ source, sourceLayer, id }, { [key]: true });
    }
    this.set({ selected: next });
  }
}

export function createAttributeTable(map: Map, options: AttributeTableOptions): AttributeTable {
  return new AttributeTableStore(map, options);
}
