// The showcase's attribute table (mbmap/ui's createAttributeTable over the places' source): sorted,
// filtered (folded as the search folds), paged, a row's click selecting and fitting to the place;
// columns added by expression and function with createFieldEditor, renamed and removed.
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
  const query = page.locator("#table input[type=search]");
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
  // Field calculation: a column by expression, one by function on the selection, renamed and removed.
  const fields = await page.evaluate(async () => {
    const [t, e] = [window.__table, window.__fields];
    const source = window.__map.getSource("places");
    const before = (await source.getData()).features.map((f) => Object.keys(f.properties));
    await e.addColumn("label", ["concat", ["get", "name"], "（", ["get", "kind"], "）"]);
    const added = { columns: t.state.columns, first: t.state.rows[0].properties.label, name: t.state.rows[0].properties.name, kind: t.state.rows[0].properties.kind };
    t.select("上野駅");
    await e.calculate("len", (row) => row.properties.name.length, { only: "selected" });
    t.setQuery("名所");
    await e.calculate("sight", ["==", ["get", "kind"], "名所"], { only: "filtered" });
    const sights = (await source.getData()).features.filter((f) => "sight" in f.properties).map((f) => f.properties.sight);
    t.setQuery("");
    await e.removeColumn("sight");
    const lens = (await source.getData()).features.filter((f) => "len" in f.properties).map((f) => [f.properties.name, f.properties.len]);
    t.clear();
    await e.renameColumn("label", "title");
    const renamed = { columns: t.state.columns, keys: Object.keys((await source.getData()).features[0].properties).filter((k) => k !== "len") };
    let refused = null;
    await e.addColumn("bad", ["nope"]).catch((e) => (refused = e.message));
    const exists = await e.addColumn("name").then(() => null, (e) => e.message);
    await e.removeColumn("title");
    await e.removeColumn("len");
    const after = (await source.getData()).features.map((f) => Object.keys(f.properties));
    const direct = window.__map.evaluateExpression(["*", ["get", "n"], 2], [{ properties: { n: 21 } }, { properties: {} }]);
    return { added, lens, sights, renamed, refused, exists, columns: t.state.columns, restored: JSON.stringify(after) === JSON.stringify(before), direct };
  });
  // The same through the page's form.
  const headsAre = (want) =>
    page.waitForFunction((w) => JSON.stringify([...document.querySelectorAll("#table th")].map((th) => th.textContent)) === w, JSON.stringify(want), { timeout: 5000 }).then(() => true, () => false);
  const form = async (action, values) => {
    for (const [k, v] of Object.entries(values)) await page.fill(`#field-${k}`, v);
    await page.click(`[data-field=${action}]`);
    await page.waitForFunction(() => document.getElementById("field-status").textContent !== "");
    const status = await page.evaluate(() => document.getElementById("field-status").textContent);
    await page.evaluate(() => (document.getElementById("field-status").textContent = ""));
    return status;
  };
  const typed = { calculated: await form("calculate", { name: "label", expression: '["concat", ["get", "name"], "!"]' }) };
  typed.added = await headsAre(["名前", "種別", "label"]);
  typed.cell = await page.evaluate(() => document.querySelector("#table tbody tr td:last-child").textContent);
  typed.renamed = await form("rename", { name: "label", to: "名称" });
  typed.afterRename = await headsAre(["名前", "種別", "名称"]);
  typed.bad = await form("calculate", { name: "x", expression: "[oops" });
  typed.removed = await form("remove", { name: "名称" });
  typed.after = await headsAre(["名前", "種別"]);
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
    JSON.stringify(picked.both) === JSON.stringify({ selected: ["上野駅", "品川駅"], shinagawa: true }) && JSON.stringify(picked.cleared) === JSON.stringify([false, false]) &&
    JSON.stringify(fields.added.columns) === JSON.stringify(["name", "kind", "label"]) && fields.added.first === `${fields.added.name}（${fields.added.kind}）` &&
    JSON.stringify(fields.lens) === JSON.stringify([["上野駅", 3]]) &&
    fields.sights.length === expected.sights.length && fields.sights.every((v) => v === true) && JSON.stringify(fields.renamed.columns) === JSON.stringify(["name", "kind", "title", "len"]) &&
    fields.renamed.keys.indexOf("title") === fields.renamed.keys.length - 1 && /unsupported: expression nope/.test(fields.refused ?? "") && /exists/.test(fields.exists ?? "") &&
    JSON.stringify(fields.columns) === JSON.stringify(["name", "kind"]) && fields.restored && JSON.stringify(fields.direct) === JSON.stringify([42, null]) &&
    typed.added && typed.cell === `${initial.names[0]}!` && typed.afterRename && typed.bad === "式を JSON で書いてください" && typed.after;
  return { ok, fields, typed, initial: { total: initial.total, pages: initial.pages, names: initial.names }, asc: asc.names, desc: desc.names, sights: sights.filtered, folded: folded.names, paged, chosen: chosen.selected, picked };
}
