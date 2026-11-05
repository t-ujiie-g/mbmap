// The showcase's search (mbmap/search, no server): place names, coordinates in
// three forms (plane rectangular and UTM through mbmap/analysis), and the input
// box driven from the keyboard, each choice moving the map.
import { awaitAfter } from "./step.mjs";

export async function searchChecks(page) {
  const find = (query) =>
    page.evaluate(async (query) => {
      const s = window.__search;
      s.setQuery(query);
      await s.submit();
      return s.state.results.map((r) => ({ label: r.label, provider: r.provider, lng: r.lngLat.lng, lat: r.lngLat.lat, detail: r.detail ?? null }));
    }, query);
  const names = await find("とうきょう");
  const kanji = await find("東京");
  const decimal = await find("35.6586, 139.7454");
  const plane = await find("第IX系 X -35367.23 Y -5995.19");
  const utm = await find("54N 388708 3949480");
  const typed = page.locator("#search input").first();
  await typed.fill("東京タワー");
  await page.waitForFunction(() => !window.__search.state.loading && window.__search.state.results.length === 1 && window.__search.state.results[0].label === "東京タワー");
  // Keys that confirm a Japanese IME conversion are the IME's: neither the composing Enter nor
  // Safari's confirming one (keyCode 229) chooses a result.
  const imeIgnored = await page.evaluate(async () => {
    const input = document.querySelector("#search input");
    for (const init of [{ key: "Enter", isComposing: true }, { key: "Enter", keyCode: 229 }, { key: "ArrowDown", isComposing: true }]) {
      input.dispatchEvent(new KeyboardEvent("keydown", { ...init, bubbles: true, cancelable: true }));
    }
    await new Promise((r) => setTimeout(r, 300));
    const s = window.__search.state;
    return s.selected?.label !== "東京タワー" && s.active === -1 && s.open && !window.__map.isMoving();
  });
  await typed.press("ArrowDown");
  await awaitAfter(page, "search: Enter on a result", () => typed.press("Enter"), { event: "moveend" });
  const chosen = await page.evaluate(() => ({ label: window.__search.state.selected?.label, center: window.__map.getCenter(), open: window.__search.state.open }));
  const near = (r, lng, lat, tol) => r && Math.abs(r.lng - lng) < tol && Math.abs(r.lat - lat) < tol;
  const ok =
    names.length === 0 &&
    kanji.map((r) => r.label).join() === "東京駅,東京タワー,東京スカイツリー" && kanji.every((r) => r.provider === "地点") &&
    near(decimal[0], 139.7454, 35.6586, 1e-12) && decimal[0].provider === "座標" &&
    plane.length === 1 && plane[0].detail === "第IX系" && near(plane[0], 139.7671, 35.6812, 1e-6) &&
    utm.length === 1 && utm[0].detail === "UTM 54N" && near(utm[0], 139.77, 35.68, 0.01) &&
    imeIgnored && chosen.label === "東京タワー" && !chosen.open && near({ lng: chosen.center.lng, lat: chosen.center.lat }, 139.7454, 35.6586, 1e-3);
  return { ok, kanji, decimal: decimal[0], plane: plane[0], utm: utm[0], imeIgnored, chosen };
}
