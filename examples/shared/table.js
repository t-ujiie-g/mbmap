// The places as an attribute table from `mbmap/ui`: sorted by header, filtered, paged; a row's
// click selects the place (the places layer's `selected` feature state) and fits the map to it;
// its columns are edited by a field editor.
import { cellText, createAttributeTable, createFieldEditor } from "mbmap/ui";

/** Each column's key and heading. */
export const TABLE_COLUMNS = [
  ["name", "名前"],
  ["kind", "種別"],
];

export function createPlacesTable(map) {
  const table = createAttributeTable(map, { source: "places", columns: TABLE_COLUMNS.map(([k]) => k), pageSize: 6, locale: "ja" });
  window.__table = table;
  window.__fields = createFieldEditor(map, { source: "places", table });
  return table;
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
  box.append(query, grid, pager);
  const draw = (s) => {
    const head = el("tr");
    for (const [key, title] of TABLE_COLUMNS) {
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
      tr.append(...TABLE_COLUMNS.map(([key]) => el("td", { textContent: cellText(row.properties[key]) })));
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
