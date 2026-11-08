// The places as an attribute table from `mbmap/ui`: sorted by header, filtered, paged; a row's
// click selects the place (the places layer's `selected` feature state) and fits the map to it;
// its columns are added, computed by expression, renamed and removed with a field editor.
import { cellText, createAttributeTable, createFieldEditor } from "mbmap/ui";

/** Each column's key and heading. */
export const TABLE_COLUMNS = [
  ["name", "名前"],
  ["kind", "種別"],
];

export function createPlacesTable(map) {
  const table = createAttributeTable(map, { source: "places", columns: TABLE_COLUMNS.map(([k]) => k), pageSize: 6, locale: "ja" });
  window.__table = table;
  return table;
}

/** The places' field editor, its columns shown by `table`. */
export function createPlacesFields(map, table) {
  const fields = createFieldEditor(map, { source: "places", table });
  window.__fields = fields;
  return fields;
}

/** The columns shown as [key, heading]: the known ones by name, the others by their key. */
export function tableHeadings(s) {
  const titles = Object.fromEntries(TABLE_COLUMNS);
  return s.columns.map((k) => [k, Object.hasOwn(titles, k) ? titles[k] : k]);
}

/** The field form's starting values: a column name, its expression (JSON), the name to rename it to. */
export const FIELD_DEFAULTS = { name: "label", expression: '["concat", ["get", "name"], "（", ["get", "kind"], "）"]', to: "名称" };

/** The field form's placeholders, by the keys of FIELD_DEFAULTS. */
export const FIELD_PLACEHOLDERS = { name: "列名", expression: "式（JSON）", to: "新しい名前" };

/** The form's operations as [action, label]. */
export const FIELD_ACTIONS = [["calculate", "計算"], ["rename", "名前を変える"], ["remove", "削除"]];

/** Runs field `action` with the form's `values`; resolves to what to tell the user. */
export async function runField(fields, action, { name, expression, to }) {
  try {
    if (action === "calculate") {
      let expr;
      try {
        expr = JSON.parse(expression);
      } catch {
        return "式を JSON で書いてください";
      }
      await fields.calculate(name, expr);
      return `「${name}」を計算しました`;
    }
    if (action === "rename") {
      await fields.renameColumn(name, to);
      return `「${name}」を「${to}」にしました`;
    }
    await fields.removeColumn(name);
    return `「${name}」を消しました`;
  } catch (err) {
    return String(err.message).replace(/^mbmap: /, "");
  }
}

/** The heading's sort mark and its `aria-sort`. */
export function sortOf(state, column) {
  const d = state.sort?.column === column ? state.sort.direction : null;
  return { mark: d === "asc" ? " ▲" : d === "desc" ? " ▼" : "", aria: d === "asc" ? "ascending" : d === "desc" ? "descending" : "none" };
}

/** "3 / 21 件" (shown of all), and the page as "1 / 4". */
export function tableCounts(s) {
  return { count: s.filtered === s.total ? `${s.total} 件` : `${s.filtered} / ${s.total} 件`, page: `${s.page + 1} / ${s.pages}` };
}

/** Selects the row (Shift adds it to the selection) and fits the map to it. */
export function chooseRow(table, row, e) {
  if (row.id === null) return;
  table.select(row.id, { add: e.shiftKey });
  table.zoomTo(row.id);
}

/** Enter in the query box chooses the first row, unless it confirms an IME conversion (keyCode 229: Safari's). */
export function onTableKey(table, e) {
  if (e.isComposing || e.keyCode === 229 || e.key !== "Enter") return;
  const first = table.state.rows[0];
  if (first) chooseRow(table, first, e);
}

const el = (tag, props = {}) => Object.assign(document.createElement(tag), props);

/** The table drawn into `#table` with plain DOM (text through `textContent`). */
export function mountTable(map) {
  const table = createPlacesTable(map);
  const fields = createPlacesFields(map, table);
  const box = document.getElementById("table");
  const query = el("input", { type: "search", placeholder: "名前や種別で絞り込む" });
  query.addEventListener("input", () => table.setQuery(query.value));
  query.addEventListener("keydown", (e) => onTableKey(table, e));
  const grid = el("table", { className: "attributes" });
  const pager = el("div", { className: "table-pager" });
  const prev = el("button", { textContent: "◀" });
  const next = el("button", { textContent: "▶" });
  const page = el("span");
  const count = el("span", { className: "table-count" });
  prev.addEventListener("click", () => table.previous());
  next.addEventListener("click", () => table.next());
  pager.append(prev, page, next, count);
  const form = el("div", { className: "field-form" });
  const inputs = Object.fromEntries(
    Object.entries(FIELD_DEFAULTS).map(([k, v]) => [k, el("input", { id: `field-${k}`, value: v, placeholder: FIELD_PLACEHOLDERS[k] })]),
  );
  const status = el("p", { id: "field-status", className: "hint" });
  const buttons = el("div", { className: "chips" });
  for (const [action, label] of FIELD_ACTIONS) {
    const b = el("button", { textContent: label });
    b.dataset.field = action;
    b.addEventListener("click", async () => {
      status.textContent = await runField(fields, action, { name: inputs.name.value, expression: inputs.expression.value, to: inputs.to.value });
    });
    buttons.append(b);
  }
  form.append(inputs.name, inputs.expression, inputs.to, buttons, status);
  box.append(query, grid, pager, form);
  const draw = (s) => {
    const head = el("tr");
    for (const [key, title] of tableHeadings(s)) {
      const sort = sortOf(s, key);
      const th = el("th");
      th.setAttribute("aria-sort", sort.aria);
      const button = el("button", { textContent: title + sort.mark });
      button.addEventListener("click", () => table.setSort(key));
      th.append(button);
      head.append(th);
    }
    const rows = s.rows.map((row) => {
      const tr = el("tr");
      tr.setAttribute("aria-selected", String(row.id !== null && s.selected.includes(String(row.id))));
      tr.append(...s.columns.map((key) => el("td", { textContent: cellText(row.properties[key]) })));
      tr.addEventListener("click", (e) => chooseRow(table, row, e));
      return tr;
    });
    grid.replaceChildren(el("thead"), el("tbody"));
    grid.tHead.append(head);
    grid.tBodies[0].append(...rows);
    const c = tableCounts(s);
    page.textContent = c.page;
    count.textContent = c.count;
    prev.disabled = s.page === 0;
    next.disabled = s.page >= s.pages - 1;
  };
  table.subscribe(draw);
  draw(table.state);
  return table;
}
