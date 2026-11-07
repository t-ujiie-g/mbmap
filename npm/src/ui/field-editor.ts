// Field calculation on a GeoJSON source: columns added, computed (style expressions or functions),
// renamed and removed in the source's data, with an attribute table kept up to date.
import type { Map } from "../index";
import type { AttributeTable } from "./attribute-table";
import { featuresOf, rowsOf, type TableRow } from "./table-rows";
import { checkColumn, removeColumn, renameColumn, setColumn } from "./table-fields";

/** `source`: the GeoJSON source to edit; `table`: an attribute table of it, whose rows `only` picks from and whose columns follow the edits. */
export interface FieldEditorOptions {
  source: string;
  table?: AttributeTable;
}

/** Which features `calculate` sets: every one (default), the table's `"filtered"` rows or its `"selected"` ones. */
export interface CalculateOptions {
  only?: "filtered" | "selected";
}

export interface FieldEditor {
  /**
   * Sets `column` (added if new) of every feature, or `only` some, to `value`: a style expression
   * evaluated for each (`Map.evaluateExpression`; `["id"]` the row's id, promoted ids included), or
   * a function of its row (values from `mbmap/analysis`, say). Writes the data with `setData`.
   */
  calculate(column: string, value: unknown, options?: CalculateOptions): Promise<void>;
  /** `calculate` of a column no feature has yet (`value` default null). */
  addColumn(column: string, value?: unknown, options?: CalculateOptions): Promise<void>;
  removeColumn(column: string): Promise<void>;
  /** Renames column `from`, which keeps its place among each feature's keys; throws if a feature has `to`. */
  renameColumn(from: string, to: string): Promise<void>;
}

type Feature = { properties?: Record<string, unknown> | null };

class Editor implements FieldEditor {
  #map: Map;
  #options: FieldEditorOptions;

  constructor(map: Map, options: FieldEditorOptions) {
    this.#map = map;
    this.#options = options;
  }

  calculate(column: string, value: unknown, { only }: CalculateOptions = {}): Promise<void> {
    checkColumn(column);
    const table = this.#options.table;
    if (only && !table) throw new Error("mbmap: field editor: `only` needs a table");
    return this.#edit((features, rows) => {
      const passing = new Set(only === "filtered" ? table!.passing(rows) : []);
      const selected = new Set(table?.state.selected);
      const indices = rows.flatMap((r, i) => (!only || (only === "filtered" ? passing.has(r) : r.id !== null && selected.has(String(r.id))) ? [i] : []));
      const picked = indices.map((i) => rows[i]);
      setColumn(features, column, indices, typeof value === "function" ? picked.map((r) => value(r)) : this.#map.evaluateExpression(value, picked));
    }, (columns) => (columns.includes(column) ? columns : [...columns, column]));
  }

  addColumn(column: string, value: unknown = null, options?: CalculateOptions): Promise<void> {
    return this.#edit((features) => {
      if (features.some((f) => f.properties && Object.hasOwn(f.properties, column))) throw new Error(`mbmap: field editor: column ${JSON.stringify(column)} exists`);
    }).then(() => this.calculate(column, value, options));
  }

  removeColumn(column: string): Promise<void> {
    return this.#edit((features) => removeColumn(features, column), (columns) => columns.filter((c) => c !== column));
  }

  async renameColumn(from: string, to: string): Promise<void> {
    await this.#edit((features) => renameColumn(features, from, to), (columns) => columns.map((c) => (c === from ? to : c)));
    const sort = this.#options.table?.state.sort;
    if (sort?.column === from) this.#options.table!.setSort(to, sort.direction);
  }

  /**
   * Reads the source's data, lets `change` edit its features (with a row for each) and, given
   * `columns`, sets the data back and gives the table the columns it shows changed by `columns`.
   */
  async #edit(change: (features: Feature[], rows: TableRow[]) => void, columns?: (shown: string[]) => string[]): Promise<void> {
    const source = this.#map.getSource(this.#options.source);
    if (!source?.getData || !source.setData) throw new Error("mbmap: field editor: only GeoJSON sources can be edited");
    const data = await source.getData();
    const features = featuresOf(data) as Feature[];
    change(features, features.map((f) => rowsOf([f], source.promoteId as string | undefined)[0]));
    if (!columns) return;
    source.setData(data);
    const table = this.#options.table;
    if (table) {
      await table.refresh();
      const next = columns(table.state.columns);
      if (next.join("\0") !== table.state.columns.join("\0")) table.setColumns(next);
    }
  }
}

export function createFieldEditor(map: Map, options: FieldEditorOptions): FieldEditor {
  return new Editor(map, options);
}
