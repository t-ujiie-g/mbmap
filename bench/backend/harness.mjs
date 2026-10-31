// Phase 0 backend comparison harness. Environment-agnostic (Node or Worker).
//
// Every variant decodes the same buffer of zigzag varint pairs (MVT-like
// geometry deltas) into absolute Float32 coordinates and hands the result to
// JS as a Float32Array that owns its ArrayBuffer (i.e. can be transferred
// with postMessage). Each iteration is split into three phases:
//   in     : getting the tile bytes to where the decoder can read them
//   decode : the decode loop itself
//   out    : getting a transferable Float32Array of the result
// For linear-memory variants `outView` (a zero-copy view, not transferable)
// is recorded as well.

export const DEFAULTS = { pairs: 500_000, warmup: 15, iterations: 40, seed: 42 };

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Delta distribution roughly shaped like z14 urban MVT geometry:
// mostly 1-byte varints, some 2-byte, a few 3-byte.
export function makeInput(pairs, seed) {
  const rnd = mulberry32(seed);
  const bytes = [];
  for (let i = 0; i < pairs * 2; i++) {
    const r = rnd();
    const mag = r < 0.7 ? 64 : r < 0.95 ? 8192 : 1 << 20;
    const d = Math.floor((rnd() * 2 - 1) * mag);
    let v = ((d << 1) ^ (d >> 31)) >>> 0;
    while (v >= 0x80) {
      bytes.push((v & 0x7f) | 0x80);
      v >>>= 7;
    }
    bytes.push(v);
  }
  return Uint8Array.from(bytes);
}

// Hand-written JS reference, in the style of the `pbf` package.
export function decodeJs(src, out) {
  const len = src.length;
  let pos = 0, n = 0, x = 0, y = 0;
  while (pos < len) {
    let b = src[pos++];
    let v = b & 0x7f;
    let shift = 7;
    while (b >= 0x80) {
      b = src[pos++];
      v |= (b & 0x7f) << shift;
      shift += 7;
    }
    const d = (v >> 1) ^ -(v & 1);
    if ((n & 1) === 0) out[n] = x += d;
    else out[n] = y += d;
    n++;
  }
  return n;
}

function checksum(f32) {
  let h = 0;
  for (let i = 0; i < f32.length; i++) h = (h * 31 + f32[i]) | 0;
  return h;
}

function stats(xs) {
  const s = [...xs].sort((a, b) => a - b);
  const q = (p) => s[Math.min(s.length - 1, Math.floor(p * s.length))];
  return { median: q(0.5), p10: q(0.1), p90: q(0.9), min: s[0] };
}

// Variant factories. Each returns { prepare(input), iter() -> phases }.
function variants({ js, wasm, wasmOpt, wasmgc, wasmgcOpt }, count) {
  const list = [];

  list.push({
    name: "js-baseline",
    note: "hand-written JS, writes Float32Array directly",
    make(input) {
      return () => {
        const t0 = performance.now();
        const out = new Float32Array(count);
        const t1 = performance.now();
        decodeJs(input, out);
        const t2 = performance.now();
        return { in: 0, decode: t2 - t1, out: t1 - t0, result: out };
      };
    },
  });

  if (js) {
    list.push({
      name: "mbt-js",
      note: "FixedArray[Byte]=Uint8Array in, FixedArray[Float]=Array out, then new Float32Array(arr)",
      make(input) {
        const arr = js.alloc_floats(count);
        return () => {
          const t0 = performance.now();
          js.decode(input, input.length, arr);
          const t1 = performance.now();
          const out = new Float32Array(arr);
          const t2 = performance.now();
          return { in: 0, decode: t1 - t0, out: t2 - t1, result: out };
        };
      },
    });
    list.push({
      name: "mbt-js-ffi",
      note: "Uint8Array in, writes into a JS Float32Array via extern \"js\"",
      make(input) {
        return () => {
          const t0 = performance.now();
          const out = new Float32Array(count);
          const t1 = performance.now();
          js.decode_f32(input, input.length, out);
          const t2 = performance.now();
          return { in: 0, decode: t2 - t1, out: t1 - t0, result: out };
        };
      },
    });
  }

  const linear = (name, note, e, useMem) => ({
    name,
    note,
    make(input) {
      let src, dst;
      if (e.__gc) {
        // wasm-gc: MoonBit objects live on the GC heap, so reserve our own
        // region in the (otherwise unused) linear memory.
        const need = input.length + count * 4 + 65536;
        const pages = Math.ceil((need - e.memory.buffer.byteLength) / 65536);
        if (pages > 0) e.grow_memory(pages);
        src = 65536;
        dst = src + ((input.length + 7) & ~7);
      } else {
        src = e.alloc_bytes(input.length);
        dst = e.alloc_floats(count);
      }
      return () => {
        const t0 = performance.now();
        new Uint8Array(e.memory.buffer, src, input.length).set(input);
        const t1 = performance.now();
        if (useMem) e.decode_mem(src, input.length, dst);
        else e.decode(src, input.length, dst);
        const t2 = performance.now();
        const view = new Float32Array(e.memory.buffer, dst, count);
        const t3 = performance.now();
        const out = view.slice();
        const t4 = performance.now();
        return { in: t1 - t0, decode: t2 - t1, out: t4 - t2, outView: t3 - t2, result: out };
      };
    },
  });

  for (const [suffix, e] of [["", wasm], ["+opt", wasmOpt]]) {
    if (!e) continue;
    list.push(linear(`mbt-wasm${suffix}`, "linear memory; safe FixedArray decode; view + slice()", e, false));
    list.push(linear(`mbt-wasm-raw${suffix}`, "linear memory; raw load/store via inline wasm; view + slice()", e, true));
  }

  for (const [suffix, gc] of [["", wasmgc], ["+opt", wasmgcOpt]]) {
    if (!gc) continue;
    list.push({
      name: `mbt-wasm-gc${suffix}`,
      note: "GC arrays; per-element exported set_u8/get_f32 across the boundary",
      make(input) {
        const src = gc.alloc_bytes(input.length);
        const dst = gc.alloc_floats(count);
        return () => {
          const t0 = performance.now();
          for (let i = 0; i < input.length; i++) gc.set_u8(src, i, input[i]);
          const t1 = performance.now();
          gc.decode(src, input.length, dst);
          const t2 = performance.now();
          const out = new Float32Array(count);
          for (let i = 0; i < count; i++) out[i] = gc.get_f32(dst, i);
          const t3 = performance.now();
          return { in: t1 - t0, decode: t2 - t1, out: t3 - t2, result: out };
        };
      },
    });
    list.push(linear(
      `mbt-wasm-gc-mem${suffix}`,
      "wasm-gc code, I/O through linear memory with inline wasm; view + slice()",
      Object.assign(Object.create(null), gc, { __gc: true }),
      true,
    ));
    list.push({
      name: `mbt-wasm-gc-copy${suffix}`,
      note: "wasm-gc; JS->linear memory, in-wasm copy to GC Bytes, safe decode, in-wasm copy back; view + slice()",
      make(input) {
        const need = input.length + count * 4 + 65536;
        const pages = Math.ceil((need - gc.memory.buffer.byteLength) / 65536);
        if (pages > 0) gc.grow_memory(pages);
        const srcAddr = 65536;
        const dstAddr = srcAddr + ((input.length + 7) & ~7);
        const src = gc.alloc_bytes(input.length);
        const dst = gc.alloc_floats(count);
        return () => {
          const t0 = performance.now();
          new Uint8Array(gc.memory.buffer, srcAddr, input.length).set(input);
          gc.bytes_from_mem(srcAddr, input.length, src);
          const t1 = performance.now();
          gc.decode(src, input.length, dst);
          const t2 = performance.now();
          gc.floats_to_mem(dst, count, dstAddr);
          const out = new Float32Array(gc.memory.buffer, dstAddr, count).slice();
          const t3 = performance.now();
          return { in: t1 - t0, decode: t2 - t1, out: t3 - t2, result: out };
        };
      },
    });
  }
  return list;
}

// Allocation-heavy workload: one Array of boxed points per feature.
function allocJs(features, ring) {
  let sum = 0;
  for (let f = 0; f < features; f++) {
    const pts = [];
    for (let i = 0; i < ring; i++) pts.push({ x: i ^ f, y: i + f });
    const p = pts[ring >> 1];
    sum = (sum + p.x - p.y + pts.length) | 0;
  }
  return sum;
}

export function runAllocSuite(modules, { features = 100_000, ring = 32, warmup = 5, iterations = 20 } = {}) {
  const impls = [["js-baseline", (f, r) => allocJs(f, r)]];
  for (const [key, name] of [["js", "mbt-js"], ["wasm", "mbt-wasm"], ["wasmOpt", "mbt-wasm+opt"], ["wasmgc", "mbt-wasm-gc"], ["wasmgcOpt", "mbt-wasm-gc+opt"]]) {
    if (modules[key]) impls.push([name, (f, r) => modules[key].alloc_churn(f, r)]);
  }
  const expected = allocJs(features, ring);
  const rows = [];
  for (const [name, fn] of impls) {
    for (let i = 0; i < warmup; i++) fn(features, ring);
    const xs = [];
    let got;
    for (let i = 0; i < iterations; i++) {
      const t0 = performance.now();
      got = fn(features, ring);
      xs.push(performance.now() - t0);
    }
    rows.push({ name, correct: got === expected, time: stats(xs) });
  }
  return { params: { features, ring, points: features * ring, warmup, iterations }, rows };
}

export function runSuite(modules, opts = {}) {
  const { pairs, warmup, iterations, seed } = { ...DEFAULTS, ...opts };
  const input = makeInput(pairs, seed);
  const count = pairs * 2;
  const ref = new Float32Array(count);
  decodeJs(input, ref);
  const refSum = checksum(ref);

  const rows = [];
  for (const v of variants(modules, count)) {
    let iter;
    try {
      iter = v.make(input);
    } catch (err) {
      rows.push({ name: v.name, note: v.note, error: String(err) });
      continue;
    }
    for (let i = 0; i < warmup; i++) iter();
    const phases = { in: [], decode: [], out: [], outView: [], total: [] };
    let last;
    for (let i = 0; i < iterations; i++) {
      const r = iter();
      phases.in.push(r.in);
      phases.decode.push(r.decode);
      phases.out.push(r.out);
      if (r.outView !== undefined) phases.outView.push(r.outView);
      phases.total.push(r.in + r.decode + r.out);
      last = r.result;
    }
    const row = { name: v.name, note: v.note, correct: checksum(last) === refSum };
    for (const [k, xs] of Object.entries(phases)) if (xs.length) row[k] = stats(xs);
    rows.push(row);
  }
  return {
    params: { pairs, warmup, iterations, seed, inputBytes: input.length, outputFloats: count },
    rows,
  };
}
