// services.wasm's reads, for its worker and the golden (bench/services/esri-golden.mjs).

import { hostNumber, MAX_INPUT_BYTES, writeInput } from "../../wasmio/js/host.mjs";
import { tableToGeoJSON, withIds } from "../../wasmio/js/table.mjs";

const decoder = new TextDecoder();

/** The imports of services.wasm, whose exports `exports()` gives once instantiated. */
export const servicesImports = (exports) => ({ host: { number: hostNumber(() => exports().memory) } });

// The bytes an export wrote, or the error it reported (-2: out of memory, else minus a message length).
function output(wasm, n) {
  if (n === -2) throw new Error("out of memory");
  const at = wasm.output_addr();
  if (n < 0) throw new Error(decoder.decode(new Uint8Array(wasm.memory.buffer, at, -n)));
  return new Uint8Array(wasm.memory.buffer, at, n).slice();
}

/** An ArcGIS query result (`format` "json" or "pbf") as GeoJSON features and its `exceededTransferLimit`. */
export function readEsri(wasm, bytes, format) {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength > MAX_INPUT_BYTES || (format !== "json" && format !== "pbf")) {
    throw new Error("invalid arguments");
  }
  writeInput(wasm, [bytes]);
  const fc = tableToGeoJSON(output(wasm, wasm.read_esri(format === "pbf" ? 1 : 0)));
  const exceeded = wasm.exceeded() === 1;
  const n = wasm.ids_out();
  return { features: (n > 0 ? withIds(fc, output(wasm, n)) : fc).features, exceeded };
}
