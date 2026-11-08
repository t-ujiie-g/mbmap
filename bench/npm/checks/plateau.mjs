// examples/plateau with ?local=1: PLATEAU's buildings around Tokyo Station (bench/fixtures/plateau-chiyoda)
// are refined and drawn, a click lists the building's attributes, and the checkbox swaps them for the
// map's extruded buildings and back. Without the fixture (CI) the page says it could not read the tileset.
import { commonestShare } from "./pixels.mjs";

const settled = () =>
  new Promise((done) => {
    let last = "";
    let same = 0;
    const check = () => {
      const layer = window.__layer;
      const now = layer.selected.map((t) => t.path).sort().join();
      same = now === last && layer.idle && layer.selected.length > 0 && !window.__map.isMoving() ? same + 1 : 0;
      last = now;
      if (same > 10) done();
      else {
        window.__map.triggerRepaint();
        requestAnimationFrame(check);
      }
    };
    requestAnimationFrame(check);
  });

export async function plateauChecks(page) {
  await page.waitForFunction(() => window.__loaded !== undefined);
  const fixture = await page.evaluate(async () => (await fetch(new URL("../../bench/fixtures/plateau-chiyoda/tileset.json", location.href), { method: "HEAD" })).ok);
  if (!fixture) {
    await page.waitForFunction(() => document.getElementById("status").textContent.includes("読めませんでした"));
    return [true, { skipped: "no fixtures" }];
  }
  await page.evaluate(() => window.__layer.ready);
  await page.evaluate(settled);
  const drawn = await page.evaluate(() => ({ tiles: window.__layer.selected.length, ready: window.__layer.selected.every((t) => t.state === "ready") }));
  const blank = await commonestShare(page);
  await page.mouse.click(420, 300);
  await page.waitForFunction(() => document.querySelector("#feature table"), null, { timeout: 10000 });
  const rows = await page.$$eval("#feature > table tr", (trs) => Object.fromEntries(trs.map((tr) => [tr.cells[0].textContent, tr.cells[1].textContent])));
  await page.click("#plateau");
  const off = await page.evaluate(() => ({ layer: window.__map.getLayer("plateau") !== undefined, extruded: window.__map.getLayoutProperty("building-3d", "visibility") }));
  await page.click("#plateau");
  await page.evaluate(settled);
  const again = await page.evaluate(() => window.__layer.selected.length);
  const ok =
    drawn.tiles >= 10 && drawn.ready && blank < 0.6 &&
    /^13101-bldg-/.test(rows["建物 ID"] ?? "") && typeof rows["用途"] === "string" &&
    !off.layer && off.extruded === "visible" && again >= 10;
  return [ok, { drawn, blank, rows, off, again }];
}
