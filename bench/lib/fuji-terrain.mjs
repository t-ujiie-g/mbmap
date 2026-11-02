// bench/fixtures/gsi-dem-fuji as Terrarium PNGs under bench/dist (a form both
// mbmap and MapLibre read), and a style with them as hillshade and terrain.
import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { decodePng, encodePng, gsiToTerrarium } from "./png.mjs";
import { ROOT } from "./root.mjs";

export async function fujiTerrainStyle() {
  const from = path.join(ROOT, "bench/fixtures/gsi-dem-fuji/12");
  for (const x of await readdir(from))
    for (const f of await readdir(path.join(from, x))) {
      const { width, rgba } = decodePng(await readFile(path.join(from, x, f)));
      const file = path.join(ROOT, `bench/dist/dem-fuji-terrarium/12/${x}/${f}`);
      await mkdir(path.dirname(file), { recursive: true });
      await writeFile(file, encodePng(width, width, gsiToTerrarium(rgba)));
    }
  return {
    version: 8,
    sources: { dem: { type: "raster-dem", tiles: ["{origin}/bench/dist/dem-fuji-terrarium/{z}/{x}/{y}.png"], tileSize: 256, minzoom: 12, maxzoom: 12, encoding: "terrarium" } },
    layers: [{ id: "bg", type: "background", paint: { "background-color": "#f2efe6" } }, { id: "hillshade", type: "hillshade", source: "dem" }],
    terrain: { source: "dem", exaggeration: 1.5 },
  };
}
