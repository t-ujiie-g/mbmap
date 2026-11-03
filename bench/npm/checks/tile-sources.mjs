// Raster sources on the npm example's map, from files written here (CI has no
// tile fixtures): a tile template, a TileJSON document and a PMTiles archive,
// each a solid color; raster paint; and a transformRequest that rewrites tiles.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { encodePng } from "../../lib/png.mjs";
import { writeArchive } from "../../lib/pmtiles-writer.mjs";
import { ROOT } from "../../lib/root.mjs";
import { near, pixel } from "./pixels.mjs";
import { step } from "./step.mjs";

export async function tileSourceChecks(page) {
  const dir = path.join(ROOT, "bench/dist/pack");
  await mkdir(dir, { recursive: true });
  const solid = (r, g, b) => {
    const rgba = new Uint8Array(256 * 256 * 4);
    for (let i = 0; i < rgba.length; i += 4) rgba.set([r, g, b, 255], i);
    return encodePng(256, 256, rgba);
  };
  await writeFile(path.join(dir, "red.png"), solid(255, 0, 0));
  await writeFile(path.join(dir, "green.png"), solid(0, 255, 0));
  await writeFile(path.join(dir, "tiles.json"), JSON.stringify({ tilejson: "3.0.0", tiles: ["green.png"], attribution: "TileJSON test" }));
  await writeFile(path.join(dir, "blue.pmtiles"), writeArchive([{ z: 0, x: 0, y: 0, bytes: solid(0, 0, 255) }], { tileType: 2 }));
  const centre = () => pixel(page, 400, 300);
  await step(page, "tiles: a raster template", `map.jumpTo({ center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 });
    map.addSource("t", { type: "raster", tiles: ["/bench/dist/pack/red.png"], tileSize: 256 });
    map.addLayer({ id: "t", type: "raster", source: "t" });`);
  const red = await centre();
  await step(page, "tiles: raster-opacity", `map.setPaintProperty("t", "raster-opacity", 0.5);`);
  const half = await centre();
  await step(page, "tiles: TileJSON", `map.removeLayer("t"); map.removeSource("t");
    map.addSource("j", { type: "raster", url: "/bench/dist/pack/tiles.json", tileSize: 256 });
    map.addLayer({ id: "j", type: "raster", source: "j" });`);
  const green = await centre();
  const attribution = await page.evaluate(() => document.querySelector("#map > div")?.textContent);
  await step(page, "tiles: PMTiles", `map.removeLayer("j"); map.removeSource("j");
    map.addSource("p", { type: "raster", url: "pmtiles:///bench/dist/pack/blue.pmtiles", tileSize: 256 });
    map.addLayer({ id: "p", type: "raster", source: "p" });`);
  const blue = await centre();
  await step(page, "tiles: transformRequest", `map.removeLayer("p"); map.removeSource("p");
    window.__asked = [];
    map.setTransformRequest((url, type) => { window.__asked.push(type); return { url: url.replace("red.png", "green.png") }; });
    map.addSource("x", { type: "raster", tiles: ["/bench/dist/pack/red.png"], tileSize: 256 });
    map.addLayer({ id: "x", type: "raster", source: "x" });`);
  const transformed = await centre();
  const types = await page.evaluate(() => {
    const map = window.__map;
    map.removeLayer("x");
    map.removeSource("x");
    map.setTransformRequest(null);
    return [...new Set(window.__asked)];
  });
  const ok =
    // Half red over the light background.
    near(red, [255, 0, 0]) && half[0] > 200 && half[1] > 90 && half[1] < 170 &&
    near(green, [0, 255, 0]) && /TileJSON test/.test(attribution ?? "") &&
    near(blue, [0, 0, 255]) &&
    near(transformed, [0, 255, 0]) && JSON.stringify(types) === JSON.stringify(["Tile"]);
  return { ok, red, half, green, attribution, blue, transformed, types };
}
