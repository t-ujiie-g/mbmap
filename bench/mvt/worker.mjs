// Worker entry for the browser mvt decode bench; bundled by browser.mjs.
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { loadWasmGc, referenceTotals } from "./reference.mjs";
import { decoders, runDecodeBench } from "./bench-core.mjs";

try {
  const manifest = await (await fetch("/bench/fixtures/gsi-bvmap.manifest.json")).json();
  const tiles = [];
  for (const key of Object.keys(manifest.tiles)) {
    const buf = new Uint8Array(await (await fetch(`/bench/fixtures/gsi-bvmap/${key}.pbf`)).arrayBuffer());
    tiles.push({ key, buf, points: referenceTotals(new VectorTile(new PbfReader(buf))).points });
  }
  const mbtJs = await import("/_build/js/release/build/bench/mvt/entry/entry.js");
  const gc = await loadWasmGc(async (rel) => new Uint8Array(await (await fetch(`/${rel}`)).arrayBuffer()));
  postMessage({ env: { userAgent: navigator.userAgent, crossOriginIsolated }, ...runDecodeBench(tiles, decoders({ mbtJs, gc })) });
} catch (err) {
  postMessage({ error: String(err?.stack ?? err) });
}
