// Style rendering vs MapLibre GL JS 6.16.0 in Chromium, pixel by pixel, a small style per scene
// (scenes.mjs) on the GSI fixtures; each scene's mean and p99 must stay within its limits.
// Usage: node style/golden.mjs [--scene=name] [--shots=dir]; writes bench/results/style-golden.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";
import { compareScenes } from "./compare.mjs";
import { SCENES } from "./scenes.mjs";
import { writeSprite } from "./sprite.mjs";
import { writeFujiTerrarium } from "../lib/fuji-terrain.mjs";
import { arg } from "../lib/args.mjs";

const only = arg("scene");
await writeSprite();
await writeFujiTerrarium();
const results = await compareScenes(SCENES, { only, shots: arg("shots") });
if (!only) await writeFile(path.join(ROOT, "bench/results/style-golden.json"), `${JSON.stringify({ env: { maplibre: "6.16.0", browser: "chromium", viewport: "800x600" }, results }, null, 2)}\n`);
