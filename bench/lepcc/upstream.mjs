// Esri's LEPCC C++ at a pinned commit, fetched into bench/dist/lepcc/src (sha256-checked) and built with g++ and
// bench/lepcc/cli.cpp into bench/dist/lepcc/bin, also with AddressSanitizer (vectors annotated) for hostile
// blobs. Behind a proxy, Node's fetch needs NODE_USE_ENV_PROXY=1.
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";

export const COMMIT = "63a30e2a07cabadbad09e205e7189fb034e3431a";
const BASE = `https://raw.githubusercontent.com/Esri/lepcc/${COMMIT}/src/`;
const SOURCES = {
  "lepcc_c_api_impl.cpp": "bfdc6c467072cd36a88205cdc20db3ba0958299081c97053b39c96429a44f9aa",
  "LEPCC.cpp": "2fb74aa183df5c0d970d70823fc4a5cf2f315ff1aaa7101d10dfcf12674b3b7d",
  "LEPCC.h": "caa6351c8f36477ca216b036803b95816235a229ef79f05762608c88b8a724d7",
  "ClusterRGB.cpp": "6a71ef971bb8d5233f6408c2833aa7479234479c95b13ed95aa1035d58d6e479",
  "ClusterRGB.h": "42a33bbe20befd53715ceeb19c2c07d14708e64aef8dcdcd5412144087151001",
  "BitStuffer2.cpp": "b3e62d6e615d33cbcadc0855623108a4c87ca380963379740e2a03242d252894",
  "BitStuffer2.h": "1dafbc025b95cf8e3fb793ae5ce5e0f48c25c84fd137fbe237aba7b447310311",
  "Huffman.cpp": "4e2209bc504ba1235caecfb24af531b6a2f32730a1a6e259a87cbed7005d816b",
  "Huffman.h": "b5f287bf4d2fe8084be73a4a2704e57a0ef9784c146cd80b7db6f9f5b2542ab8",
  "BitMask.cpp": "96adf5b015e3d485663c926f656098788bf3487c0eb53baed95141693507aec0",
  "BitMask.h": "50cea9ca28d9c547faea77056211c6ebba326faa5f0887ef3c9171fc70686f4e",
  "Common.cpp": "ddccace2f0793cecd7de411e8be67c23fc2881cfeed12a6174216be378f897c1",
  "Common.h": "298eda9d06cf97686477a08e5e668bc2b7ccc4c61fa5d235a9eda142cffce896",
  "Intensity.cpp": "d29204d2509423838bb6258c43eb9782ae79867ee50f24e5d97e3bb4e7b4c95b",
  "Intensity.h": "5e228f56fa81477f309d0c890e503a76f7ba3cc18a9f4f24e866bcaba5f03042",
  "FlagBytes.cpp": "f4eb6b389db17a930e255fd082017766b7d62dfd71495e2f103dd11af7efb9b4",
  "FlagBytes.h": "81dd1642e261c45c777f612c737ef069486e4bc089742b375b80677e2a24cbbb",
  "utl_const_array.h": "e0b3af96fa158c8719ebe0d4be94b5172b158cd90d05e24d5cc6315a1376f7b7",
  "include/lepcc_c_api.h": "62ca32f86486ab8f7ce34234c1f16328af06694a74174af8e95537b3aab49269",
  "include/lepcc_types.h": "41d17be65033fd6d89e4419d03c9b562681769b2bdbcf87d5ae5d97c015984b2",
};
const DIST = path.join(ROOT, "bench/dist/lepcc");
const SRC = path.join(DIST, "src");
const BIN = path.join(DIST, "bin");
export const CLI = path.join(BIN, "lepcc-cli");
export const CLI_ASAN = path.join(BIN, "lepcc-cli-asan");

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

/** Fetches (once) and checks the sources, then builds both command lines if missing. */
export async function buildUpstream() {
  for (const [name, hash] of Object.entries(SOURCES)) {
    const file = path.join(SRC, name);
    let bytes = existsSync(file) ? await readFile(file) : null;
    if (!bytes || sha256(bytes) !== hash) {
      const res = await fetch(BASE + name);
      if (!res.ok) throw new Error(`${name}: HTTP ${res.status} (set NODE_USE_ENV_PROXY=1 behind a proxy)`);
      bytes = Buffer.from(await res.arrayBuffer());
      if (sha256(bytes) !== hash) throw new Error(`${name}: sha256 ${sha256(bytes)} differs from the pinned one`);
      await mkdir(path.dirname(file), { recursive: true });
      await writeFile(file, bytes);
    }
  }
  await mkdir(BIN, { recursive: true });
  const units = [path.join(ROOT, "bench/lepcc/cli.cpp"), ...Object.keys(SOURCES).filter((f) => f.endsWith(".cpp")).map((f) => path.join(SRC, f))];
  // No FMA contraction, so the decoder's x0 + i * cw rounds as the port's does.
  const flags = ["-std=c++11", "-ffp-contract=off", "-I", SRC, ...units];
  const builds = [
    [CLI, ["-O2", ...flags, "-o", CLI]],
    [CLI_ASAN, ["-O1", "-g", "-fsanitize=address", "-D_GLIBCXX_SANITIZE_VECTOR", "-fno-omit-frame-pointer", ...flags, "-o", CLI_ASAN]],
  ];
  // Rebuilt when cli.cpp or the flags change.
  const stamp = sha256(JSON.stringify(builds) + (await readFile(units[0])));
  const stampFile = path.join(BIN, "stamp");
  if (!existsSync(stampFile) || (await readFile(stampFile, "utf8")) !== stamp || !builds.every(([out]) => existsSync(out))) {
    for (const [, args] of builds) execFileSync("g++", args, { cwd: BIN, stdio: "inherit" });
    await writeFile(stampFile, stamp);
  }
}

function run(cli, args, input) {
  const r = spawnSync(cli, args, { input, maxBuffer: 1 << 30, cwd: BIN, env: { ...process.env, ASAN_OPTIONS: "detect_leaks=0" } });
  return r;
}

function blobOf(out) {
  const n = out.readUInt32LE(0);
  return { blob: new Uint8Array(out.subarray(4, 4 + n)), rest: out.subarray(4 + n) };
}

/** `lepcc_encodeXYZ` of interleaved x, y, z: the blob and each stored point's index in `xyz`. */
export function encodeXyz(xyz, maxX, maxY, maxZ) {
  const r = run(CLI, ["xyz", String(maxX), String(maxY), String(maxZ)], Buffer.from(xyz.buffer, xyz.byteOffset, xyz.byteLength));
  if (r.status !== 0) throw new Error(`lepcc xyz: ${r.stderr}`);
  const { blob, rest } = blobOf(r.stdout);
  return { blob, order: new Uint32Array(rest.buffer.slice(rest.byteOffset, rest.byteOffset + rest.length)) };
}

/** `lepcc_encodeRGB` of r, g, b bytes. */
export function encodeRgb(rgb) {
  const r = run(CLI, ["rgb"], Buffer.from(rgb.buffer, rgb.byteOffset, rgb.byteLength));
  if (r.status !== 0) throw new Error(`lepcc rgb: ${r.stderr}`);
  return blobOf(r.stdout).blob;
}

/** `lepcc_encodeIntensity` of a Uint16Array. */
export function encodeIntensity(values) {
  const r = run(CLI, ["intensity"], Buffer.from(values.buffer, values.byteOffset, values.byteLength));
  if (r.status !== 0) throw new Error(`lepcc intensity: ${r.stderr}`);
  return blobOf(r.stdout).blob;
}

export const KINDS = ["xyz", "rgb", "intensity"];
const EACH = [24, 3, 2];

/**
 * The C API's decoding of each `{kind, blob}` (cli.cpp's record fields, `values` typed; `status` -1 past the caps);
 * with `asan`, a record where the C++ goes out of bounds is `{crashed}` and the rest go to a new process. */
export function decodeUpstream(records, { asan = false } = {}) {
  const results = [];
  while (results.length < records.length) {
    const rest = records.slice(results.length);
    const parts = [];
    for (const { kind, blob } of rest) {
      const head = Buffer.alloc(8);
      head.writeUInt32LE(KINDS.indexOf(kind), 0);
      head.writeUInt32LE(blob.length, 4);
      parts.push(head, Buffer.from(blob.buffer, blob.byteOffset, blob.byteLength));
    }
    const r = run(asan ? CLI_ASAN : CLI, ["decode"], Buffer.concat(parts));
    const out = r.stdout;
    let at = 0;
    for (const { kind } of rest) {
      if (at + 32 > out.length) break;
      const [info, type, size, countStatus, count, status, decoded, unfilled] = [0, 1, 2, 3, 4, 5, 6, 7].map((k) => out.readUInt32LE(at + 4 * k));
      const k = KINDS.indexOf(kind);
      if (at + 32 + decoded * EACH[k] > out.length) break;
      at += 32;
      const res = { info, type, size, countStatus, count, status: status | 0, unfilled };
      if (status === 0) {
        const bytes = out.buffer.slice(out.byteOffset + at, out.byteOffset + at + decoded * EACH[k]);
        res.values = k === 0 ? new Float64Array(bytes) : k === 1 ? new Uint8Array(bytes) : new Uint16Array(bytes);
        at += decoded * EACH[k];
      }
      results.push(res);
    }
    if (r.status !== 0 && results.length < records.length) {
      if (!asan) throw new Error(`lepcc decode: exit ${r.status} ${r.signal ?? ""} ${r.stderr}`);
      results.push({ crashed: String(r.stderr).split("\n").find((l) => l.includes("ERROR")) ?? `exit ${r.status}` });
    }
  }
  return results;
}
