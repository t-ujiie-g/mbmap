// Shared by golden.mjs and the decode bench (Node and Worker).

export const WASM_GC_BUILD = "_build/wasm-gc/release/build/bench/mvt/entry/entry.wasm";

// @mapbox/vector-tile output in the shape of entry/golden.mbt's tile_to_json.
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

const WASM_PAGE = 65536;

// Instantiates the wasm-gc build; decode() copies the tile into linear memory
// from the second page on and runs decode_mem.
export async function loadWasmGc(fetchBytes) {
  const { instance } = await WebAssembly.instantiate(await fetchBytes(WASM_GC_BUILD), {});
  const e = instance.exports;
  const base = WASM_PAGE;
  return {
    exports: e,
    copyIn(buf) {
      const need = base + buf.length - e.memory.buffer.byteLength;
      if (need > 0) e.grow_memory(Math.ceil(need / WASM_PAGE));
      new Uint8Array(e.memory.buffer, base, buf.length).set(buf);
      return base;
    },
    decode(buf) {
      const points = e.decode_mem(this.copyIn(buf), buf.length);
      return { points, properties: e.last_properties(), coordSum: e.last_coord_sum() };
    },
  };
}
