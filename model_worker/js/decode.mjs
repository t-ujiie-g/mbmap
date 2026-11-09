// The wasm's meshopt and Draco decoders as gltf.ts calls them (docs/FORMATS.md "Draco output").
import { writeInput } from "../../wasmio/js/host.mjs";

/** meshopt's modes and filters as the wasm numbers them. */
const MODES = { ATTRIBUTES: 0, TRIANGLES: 1, INDICES: 2 };
const FILTERS = { NONE: 0, OCTAHEDRAL: 1, QUATERNION: 2, EXPONENTIAL: 3, COLOR: 4 };

export function meshopt(exports) {
  return (target, count, size, source, mode, filter) => {
    const m = Object.hasOwn(MODES, mode) ? MODES[mode] : undefined;
    const f = Object.hasOwn(FILTERS, filter) ? FILTERS[filter] : undefined;
    if (m === undefined || f === undefined) throw new Error(`unknown meshopt mode or filter ${mode} ${filter}`);
    writeInput(exports, [source], "meshopt data");
    const n = exports.meshopt_decode(count, size, m, f);
    if (n !== target.length) throw new Error("meshopt data could not be decoded");
    target.set(new Uint8Array(exports.memory.buffer, exports.output_addr(), n));
  };
}

/** The typed array of each Draco data type that glTF can hold (docs/FORMATS.md "Draco output"). */
const DRACO_TYPES = { 1: [Int8Array, 5120], 2: [Uint8Array, 5121], 3: [Int16Array, 5122], 4: [Uint16Array, 5123], 6: [Uint32Array, 5125], 9: [Float32Array, 5126] };

/** Decodes Draco data through the wasm's `draco_decode`; each attribute keeps its Draco attribute type as `dracoType`. */
export function draco(exports) {
  return (bytes) => {
    writeInput(exports, [bytes], "Draco data");
    const n = exports.draco_decode();
    if (n === -2) throw new Error("out of memory");
    if (n < 0) throw new Error("Draco data could not be decoded");
    const out = new Uint8Array(exports.memory.buffer.slice(exports.output_addr(), exports.output_addr() + n));
    const v = new DataView(out.buffer);
    const [faces, , count] = [v.getUint32(0, true), v.getUint32(4, true), v.getUint32(8, true)];
    const heads = [];
    for (let i = 0; i < count; i++) {
      const at = 12 + i * 12;
      heads.push({ id: v.getUint32(at, true), semantic: v.getUint8(at + 4), type: v.getUint8(at + 5), size: v.getUint8(at + 6), normalized: v.getUint8(at + 7) === 1, length: v.getUint32(at + 8, true) });
    }
    let at = 12 + count * 12;
    const indices = new Uint32Array(out.buffer.slice(at, at + faces * 12));
    at += faces * 12;
    const attributes = new Map();
    for (const h of heads) {
      const kind = DRACO_TYPES[h.type];
      if (!kind) throw new Error(`Draco data type ${h.type} has no glTF counterpart`);
      const [Typed, type] = kind;
      attributes.set(h.id, { data: new Typed(out.buffer.slice(at, at + h.length)), size: h.size, type, normalized: h.normalized, dracoType: h.semantic });
      at += (h.length + 3) & ~3;
    }
    return { indices, attributes };
  };
}

/** LEPCC blob kinds as the wasm's `lepcc_decode` numbers them, and each value's size in bytes. */
const LEPCC_KINDS = { xyz: [0, 24], rgb: [1, 3], intensity: [2, 2] };

/** Decodes I3S point clouds' LEPCC blobs through the wasm's `lepcc_decode` (docs/FORMATS.md "LEPCC output"). */
export function lepcc(exports) {
  const run = (kind, bytes) => {
    const [k, each] = LEPCC_KINDS[kind];
    writeInput(exports, [bytes], `LEPCC ${kind} data`);
    const n = exports.lepcc_decode(k);
    if (n === -2) throw new Error("out of memory");
    if (n < 8) throw new Error(`LEPCC ${kind} data could not be decoded`);
    const at = exports.output_addr();
    const count = new DataView(exports.memory.buffer, at, 8).getUint32(0, true);
    if (8 + count * each !== n) throw new Error(`LEPCC ${kind} output is malformed`);
    return exports.memory.buffer.slice(at + 8, at + n);
  };
  return {
    xyz: (bytes) => new Float64Array(run("xyz", bytes)),
    rgb: (bytes) => new Uint8Array(run("rgb", bytes)),
    intensity: (bytes) => new Uint16Array(run("intensity", bytes)),
  };
}
