// Runs `wasm-opt -O3` on the wasm and wasm-gc builds of bench/backend/entry.
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";

// Features MoonBit's output uses; wasm-opt rejects the module unless they are enabled.
const FEATURES = [
  "bulk-memory", "bulk-memory-opt", "sign-ext", "nontrapping-float-to-int",
  "mutable-globals", "multivalue", "reference-types", "simd",
].map((f) => `--enable-${f}`);

const bin = path.join(ROOT, "bench/node_modules/.bin/wasm-opt");
const build = (t) => path.join(ROOT, `_build/${t}/release/build/bench/backend/entry/entry.wasm`);
mkdirSync(path.join(ROOT, "bench/dist"), { recursive: true });
execFileSync(bin, ["-O3", ...FEATURES, build("wasm"), "-o", path.join(ROOT, "bench/dist/entry.wasm-opt.wasm")], { stdio: "inherit" });
execFileSync(bin, ["-O3", ...FEATURES, "--enable-gc", build("wasm-gc"), "-o", path.join(ROOT, "bench/dist/entry.wasm-gc-opt.wasm")], { stdio: "inherit" });
