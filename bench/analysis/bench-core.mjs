// Analysis speed: Turf.js + flatbush on parsed GeoJSON against the shipped wasm
// on a loaded dataset (export calls, no worker messages). "bbox + index" includes
// computing the boxes; mbmap builds its index on the first search.
import { loadAnalysis, MEASURE } from "./load.mjs";
import * as ref from "./reference.mjs";

const median = (xs) => [...xs].sort((a, b) => a - b)[xs.length >> 1];

export async function runAnalysisBench(fetchBytes, { runs = 5 } = {}) {
  const wasm = await loadAnalysis(fetchBytes);
  const text = async (name) => new TextDecoder().decode(await fetchBytes(`bench/dist/geojson/${name}.geojson`));
  const time = (f, before = () => {}) => {
    before();
    f();
    const ts = [];
    for (let i = 0; i < runs; i++) {
      before();
      const t0 = performance.now();
      f();
      ts.push(performance.now() - t0);
    }
    return median(ts);
  };
  const rows = {};
  const row = (name, js, mbmap) => (rows[name] = { js, mbmap });

  const buildingsText = await text("buildings");
  const buildingsBytes = new TextEncoder().encode(buildingsText);
  let features = JSON.parse(buildingsText).features;
  let id = wasm.load(buildingsBytes);
  row("read (buildings)", time(() => JSON.parse(buildingsText)), time(() => wasm.dispose(wasm.load(buildingsBytes))));
  row("area", time(() => ref.areas(features)), time(() => wasm.measure(id, MEASURE.area)));
  row("length", time(() => ref.lengths(features)), time(() => wasm.measure(id, MEASURE.length)));
  row("centroid", time(() => ref.centroids(features)), time(() => wasm.measure(id, MEASURE.centroid)));
  const boxes = ref.bboxes(features);
  row("bbox", time(() => ref.bboxes(features)), time(() => wasm.measure(id, MEASURE.bbox)));
  const q = ref.queries(ref.extentOf(boxes), 1000);
  let fresh = -1;
  row(
    "bbox + index + 1000 searches",
    time(() => {
      const ix = ref.index(ref.bboxes(features));
      for (const b of q.boxes) ix.search(...b);
    }),
    time(
      () => {
        for (const b of q.boxes) wasm.search(fresh, b);
      },
      () => {
        if (fresh >= 0) wasm.dispose(fresh);
        fresh = wasm.load(buildingsBytes);
      },
    ),
  );
  wasm.dispose(fresh);
  const ix = ref.index(boxes);
  row("1000 searches", time(() => { for (const b of q.boxes) ix.search(...b); }), time(() => { for (const b of q.boxes) wasm.search(id, b); }));
  row("1000 nearest (k=10)", time(() => { for (const [x, y] of q.points) ix.neighbors(x, y, 10); }), time(() => { for (const [x, y] of q.points) wasm.nearest(id, x, y, 10); }));
  wasm.dispose(id);

  const polys = features.filter(ref.isPolygon);
  const polyId = wasm.load(new TextEncoder().encode(JSON.stringify({ type: "FeatureCollection", features: polys })));
  const pointsText = await text("points");
  const points = JSON.parse(pointsText).features;
  const pointsId = wasm.load(new TextEncoder().encode(pointsText));
  const polyIndex = ref.index(ref.bboxes(polys));
  wasm.within(pointsId, polyId);
  wasm.collect(polyId, pointsId, "alti");
  row("points within polygons", time(() => ref.pointsWithin(points, polys, polyIndex)), time(() => wasm.within(pointsId, polyId)));
  row("collect", time(() => ref.collected(polys, points, "alti")), time(() => wasm.collect(polyId, pointsId, "alti")));
  const extent = ref.extentOf(ref.bboxes(points));
  row("grid 256 x 256", time(() => ref.grid(points, extent, 256, 256)), time(() => wasm.grid(pointsId, extent, 256, 256)));
  features = null;
  return {
    params: { runs, statistic: "median of runs after one warm-up", data: { buildings: buildingsBytes.length, polygons: polys.length, points: points.length } },
    rows,
  };
}

export function printAnalysis(result) {
  console.table(Object.fromEntries(Object.entries(result.rows).map(([n, r]) => [n, {
    "js ms": r.js.toFixed(2), "mbmap ms": r.mbmap.toFixed(2), "js / mbmap": (r.js / r.mbmap).toFixed(2),
  }])));
}
