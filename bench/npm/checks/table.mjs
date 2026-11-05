// The showcase's attribute table (mbmap/ui's createAttributeTable over the places' GeoJSON source):
// sorted by a header's click, filtered by the query box (folded as the search folds), paged, and a
// row's click selecting the place (feature state) and fitting the map to it.
import { awaitAfter, openTab } from "./step.mjs";

const NAMES_PER_PAGE = 6;

export async function tableChecks(page) {
  await openTab(page, "data");
  await page.waitForFunction(() => window.__table?.state.total > 0 && !window.__table.state.loading);
  const state = () =>
    page.evaluate(() => {
      const s = window.__table.state;
      const cells = [...document.querySelectorAll("#table tbody tr")].map((tr) => [...tr.cells].map((td) => td.textContent));
      return { ...s, names: s.rows.map((r) => r.properties.name), cells, selectedRows: [...document.querySelectorAll('#table tbody tr[aria-selected="true"]')].map((tr) => tr.cells[0].textContent) };
    });
  // What the rows should be, from the source's data and the same collator.
  const expected = await page.evaluate(async () => {
    const data = await window.__map.getSource("places").getData();
    const names = data.features.map((f) => f.properties.name);
    const sorted = [...names].sort(new Intl.Collator("ja", { numeric: true }).compare);
    return { names, sorted, sights: data.features.filter((f) => f.properties.kind === "名所").map((f) => f.properties.name) };
  });
  const initial = await state();
  const header = page.locator("#table th button").first();
  await header.click();
  await page.waitForFunction(() => window.__table.state.sort?.direction === "asc");
  const asc = await state();
  await header.click();
  await page.waitForFunction(() => window.__table.state.sort?.direction === "desc");
  const desc = await state();
  const query = page.locator("#table input");
  await query.fill("名所");
  await page.waitForFunction(() => window.__table.state.query === "名所");
  const sights = await state();
  // Half-width katakana finds 東京タワー: NFKC, then katakana as hiragana.
  await query.fill("ﾀﾜｰ");
  await page.waitForFunction(() => window.__table.state.query === "ﾀﾜｰ");
  const folded = await state();
  await query.fill("");
  const paged = await page.evaluate(() => {
    const t = window.__table;
    t.setSort(null);
    t.next();
    const second = t.state.rows.map((r) => r.properties.name);
    t.goTo(99);
    const last = { page: t.state.page, pages: t.state.pages, rows: t.state.rows.length };
    t.previous();
    return { second, last, back: t.state.page };
  });
  await query.fill("上野");
  await page.waitForFunction(() => window.__table.state.rows.length === 1);
  await awaitAfter(page, "table: a row's click", () => page.locator("#table tbody tr").first().click(), { event: "moveend" });
  const chosen = await state();
  const picked = await page.evaluate(() => {
    const map = window.__map;
    const at = map.getCenter();
    const ueno = map.getFeatureState({ source: "places", id: "上野駅" });
    window.__table.select("品川駅", { add: true });
    const both = { selected: window.__table.state.selected, shinagawa: map.getFeatureState({ source: "places", id: "品川駅" }).selected };
    window.__table.clear();
    return { at, ueno, both, cleared: [map.getFeatureState({ source: "places", id: "上野駅" }).selected, map.getFeatureState({ source: "places", id: "品川駅" }).selected] };
  });
  await query.fill("");
  const near = (a, lng, lat) => Math.abs(a.lng - lng) < 1e-3 && Math.abs(a.lat - lat) < 1e-3;
  const rowsShown = (s) => JSON.stringify(s.cells.map((c) => c[0])) === JSON.stringify(s.names);
  const ok =
    initial.total === expected.names.length && initial.filtered === initial.total && JSON.stringify(initial.columns) === JSON.stringify(["name", "kind"]) &&
    JSON.stringify(initial.names) === JSON.stringify(expected.names.slice(0, NAMES_PER_PAGE)) && initial.pages === Math.ceil(initial.total / NAMES_PER_PAGE) &&
    JSON.stringify(asc.names) === JSON.stringify(expected.sorted.slice(0, NAMES_PER_PAGE)) && rowsShown(asc) &&
    JSON.stringify(desc.names) === JSON.stringify([...expected.sorted].reverse().slice(0, NAMES_PER_PAGE)) && rowsShown(desc) &&
    sights.filtered === expected.sights.length && sights.cells.length === Math.min(NAMES_PER_PAGE, expected.sights.length) && sights.cells.every((c) => c[1] === "名所") &&
    JSON.stringify(folded.names) === JSON.stringify(["東京タワー"]) &&
    JSON.stringify(paged.second) === JSON.stringify(expected.names.slice(NAMES_PER_PAGE, 2 * NAMES_PER_PAGE)) &&
    paged.last.page === initial.pages - 1 && paged.last.rows === initial.total - NAMES_PER_PAGE * (initial.pages - 1) && paged.back === initial.pages - 2 &&
    JSON.stringify(chosen.selected) === JSON.stringify(["上野駅"]) && JSON.stringify(chosen.selectedRows) === JSON.stringify(["上野駅"]) &&
    picked.ueno.selected === true && near(picked.at, 139.7774, 35.7141) &&
    JSON.stringify(picked.both) === JSON.stringify({ selected: ["上野駅", "品川駅"], shinagawa: true }) && JSON.stringify(picked.cleared) === JSON.stringify([false, false]);
  return { ok, initial: { total: initial.total, pages: initial.pages, names: initial.names }, asc: asc.names, desc: desc.names, sights: sights.filtered, folded: folded.names, paged, chosen: chosen.selected, picked };
}
