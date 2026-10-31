// @mapbox/vector-tile references for the mvt golden test and decode bench.

// @mapbox/vector-tile output in the shape of bench/entry/golden.mbt's tile_to_json.
export function referenceJson(tile) {
  const out = {};
  for (const [name, layer] of Object.entries(tile.layers)) {
    const features = [];
    for (let i = 0; i < layer.length; i++) {
      const f = layer.feature(i);
      features.push({
        id: f.id ?? null,
        type: f.type,
        properties: f.properties,
        geometry: f.loadGeometry().map((ring) => ring.map((p) => [p.x, p.y])),
      });
    }
    out[name] = { version: layer.version, extent: layer.extent, features };
  }
  return out;
}

// The per-tile work both decoders do in the bench: every feature's properties
// and full geometry. Totals double as a cross-check.
export function referenceTotals(tile) {
  let points = 0, properties = 0, coordSum = 0;
  for (const name in tile.layers) {
    const layer = tile.layers[name];
    for (let i = 0; i < layer.length; i++) {
      const f = layer.feature(i);
      properties += Object.keys(f.properties).length;
      for (const ring of f.loadGeometry()) {
        points += ring.length;
        for (const p of ring) coordSum += p.x + p.y;
      }
    }
  }
  return { points, properties, coordSum };
}
