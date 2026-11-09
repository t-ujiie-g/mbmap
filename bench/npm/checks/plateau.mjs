// examples/plateau with ?local=1: PLATEAU's buildings around Tokyo Station are drawn, a click lists a building's
// attributes, the checkbox swaps them for the map's extrusions, the 3D tools measure, sight, tint a viewshed and cut.
// Without the fixture (bench/fixtures/plateau-chiyoda; CI) the page says it could not read the tileset.
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
  // Clicks stay right of the panel (x > 330), whose buttons fly the map elsewhere.
  const tool = async (name, clicks) => {
    await page.click(`#tools input[value=${name}]`);
    for (const [x, y] of clicks) await page.mouse.click(x, y);
    await page.evaluate(() => window.__map.once("idle"));
    return page.$eval("#tool-result", (e) => e.textContent);
  };
  const measured = await tool("measure", [[450, 250], [650, 380]]);
  const sight = await tool("sight", [[420, 450], [700, 250]]);
  const viewshed = await tool("viewshed", [[600, 450]]);
  const tinted = await page.evaluate(() => window.__map.pickPosition({ x: 600, y: 450 }) !== null);
  const section = await tool("section", [[560, 300]]);
  const clipped = await page.evaluate(() => window.__map.getClipping()?.planes?.length === 1);
  await page.click("#tools input[value=feature]");
  const ok =
    drawn.tiles >= 10 && drawn.ready && blank < 0.6 &&
    /^13101-bldg-/.test(rows["建物 ID"] ?? "") && typeof rows["用途"] === "string" &&
    !off.layer && off.extruded === "visible" && again >= 10 &&
    /^直線 [\d,.]+ m・水平 [\d,.]+ m・高さの差 -?[\d,.]+ m$/.test(measured) && /^(見えます|遮られます（)/.test(sight) && viewshed.startsWith("緑") && tinted && section.startsWith("手前を切りました") && clipped;
  return [ok, { drawn, blank, rows, off, again, measured, sight, viewshed, section }];
}
