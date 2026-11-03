// CSS colors read by style's parse_color (bench/expr's js build) vs style-spec 26.5.0's parseCssColor
// (maplibre-gl 6.16.0's), channel for channel; must stay 0 differ.
// Usage: node lib/run-bundled.mjs bench/style/colors.mjs; writes bench/results/color-golden.json.
import { readFileSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { parseCssColor } from "../node_modules/@maplibre/maplibre-gl-style-spec/src/expression/types/parse_css_color.ts";
import { ROOT } from "../lib/root.mjs";

const { color_parse } = await import(pathToFileURL(path.join(ROOT, "_build/js/release/build/bench/expr/expr.js")).href);

const SOURCE = path.join(ROOT, "bench/node_modules/@maplibre/maplibre-gl-style-spec/src/expression/types/parse_css_color.ts");
const namedColors = () => [...readFileSync(SOURCE, "utf8").matchAll(/^\s+(\w+): \[\d+, \d+, \d+\],?$/gm)].map((m) => m[1]);
const NAMES = ["aliceblue", "black", "white", "rebeccapurple", "yellowgreen", "DarkSlateGrey", " Tomato ", "blac\u212a", "grey", "gray"];
const NUMBERS = ["0", "1", "-1", "+5", ".5", "5.", "-.5", "1e2", "1e+2", "1e-2", "12e1", "1.5e1", "0.1", "0.3", "254.9999", "255",
  "256", "300", "-0", "50", "100", "120", "359.5", "360", "-30", "720.25", "1e400", "-1e400", "1e-400", "0e999", "1e23",
  "0.12345678901234", "123456789012345", "1234567890.12345", "99999999999999999999", "0.30000000000000004", "3.141592653589793",
  "1e", "e1", ".", "+", "-", "1.2.3", "1-2", "+-1", "--1", "1e2e3", "1e1.5", ""];
// Past Clinger's fast path (over 15 digits, or powers of ten past \u00b122) parse_color may differ in the last bits.
const BEYOND = ["1e-23", "1.5e-30", "0.1234567890123456789", "12345678901234567890e-18", "7e-25"];
const WS = ["", " ", "  ", "\t", "\n", "\u00a0", "\u3000", "\ufeff"];

function inputs() {
  const out = new Set(NAMES);
  for (const n of namedColors()) out.add(n).add(n.toUpperCase()).add(n + "x").add(n.slice(1));
  for (const s of ["transparent", "Transparent", "none", "", " ", "constructor", "__proto__", "toString", "hasOwnProperty", "red blue", "red;"]) out.add(s);
  for (const s of ["#f0c", "#F0C", "#f0cf", "#ff00cc", "#ff00ccff", "#FF000080", "#12", "#12345", "#1234567", "#123456789", "#ggg", "#",
    "##fff", " #abc ", "#abc ", "#ab c", "# abc", "#0000", "#ffff", "#d9c9b6", "#e3ddd3"]) out.add(s);
  const fixed = [
    "rgb(255, 0, 0)", "rgba(0, 51, 255, 0.5)", "rgb(255,255,255)", "rgb(300, -5, 50%)", "rgb(1 2 3 / 50%)", "hsl(120deg 50% 50%)",
    "hsla(30, 19%, 90%, 0.4)", "rgb(128 0 0)", "rgb(50% 0% 0%)", "rgba(255,0,255,0.6)", "rgb(255 0 255 / 60%)", "rgb(100% 0% 100% /.6)",
    "hsl(120 50% 80%)", "hsla(120deg,50%,80%,.9)", "hsl(12e1 50% 80% / 90%)", "rgb(1, 2 3)", "rgb(1 2, 3)", "rgb(1, 2, 3 / 0.5)",
    "rgb(1 2 3, 0.5)", "rgb(1,2,3,)", "rgb(1 2 3 /)", "rgb(1,2)", "rgba(1,2,3)", "rgb(1,2,3,4,5)", "rgb (1,2,3)", "rgb(1,2,3", "rgb(1,2,3))",
    "rgb(1,2,3) x", "rgbx(1,2,3)", "rgbaa(1,2,3)", "rgb()", "rgb(,0,0)", "rgb(1.2.3,0,0)", "rgb(-1,0,0)", "rgb(1e2,0,0)", "rgb(12.5,0,0)",
    "rgba(0,0,0,.5)", "rgb(10%, 20, 30)", "rgb(10%,20%,30)", "rgb(10% 20% 30% / 40)", "rgb(1 2 3 / 2)", "rgb(1 2 3 / -1)",
    "rgb(1 2 3 / 150%)", "rgb(1 2 3 / -5%)", "rgb(1,2,3,1e-2)", "RGB(1,2,3)", "RGBA(10%,20%,30%,40%)", "rgb(\t1\n2\r3\f)",
    "rgb(1\u00a02\u30003)", "rgb( 1 , 2 , 3 , 0.5 )", "rgb(1%%,2,3)", "rgb(1 % 2 % 3 %)", "rgb(1deg, 2, 3)",
    "hsl(0,0%,0%)", "hsl(0, 100%, 50%)", "hsl(60, 100%, 50%)", "hsl(180 100% 25%)", "hsl(240, 100%, 50%)", "hsl(300, 100%, 50%)",
    "hsl(360, 100%, 50%)", "hsl(-120, 100%, 50%)", "hsl(480deg, 100%, 50%)", "hsl(120, 150%, -50%)", "hsl(120, 50, 50)",
    "hsl(120%, 50%, 50%)", "hsl(120 deg, 50%, 50%)", "hsl(120DEG, 50%, 50%)", "hsl(120rad, 50%, 50%)", "hsl(120deg50%,50%)",
    "hsl(1e400, 50%, 50%)", "hsl(-1e400, 50%, 50%)", "hsl(120, 50%, 50%, 1e400)", "hsl(1, 2%, 3% / 0.5)", "hsl(1 2% 3%, 0.5)",
    "hsla(1,2%,3%)", "hsl(1,2%,3%,4%)", "hsl(0.5turn, 1%, 1%)", "hsl(30, 19%, 90%, 0.4)", "hsl(210 13.5% 77.25%)",
    "hsla(0, 0%, 100%, 0)", "hsl(-0, 0%, 0%)", "hsl(359.999, 99.999%, 0.001%)", "hsl()", "hsl(1 2% 3%", "hsla (1, 2%, 3%)",
  ];
  for (const s of fixed) out.add(s);
  for (const n of NUMBERS) {
    out.add(`rgb(${n}, 0, 0)`).add(`rgb(0 ${n}% 0)`).add(`rgb(0% 0% ${n}%)`).add(`rgba(1, 2, 3, ${n})`).add(`rgb(1 2 3 / ${n}%)`);
    out.add(`hsl(${n}, 50%, 50%)`).add(`hsl(${n}deg 100% 50%)`).add(`hsl(200, ${n}%, 50%)`).add(`hsl(200 70% ${n}%)`).add(`hsla(20, 30%, 40%, ${n})`);
  }
  for (const a of WS) for (const b of WS) out.add(`${a}rgb(${b}1,${a}2${b},3${a})${b}`).add(`hsl(${a}1${b}2%${a}3%${b}/${a}4${b})`);
  // Random hues, saturations and lightnesses with up to 15 significant digits.
  let seed = 1;
  const rand = () => (seed = (seed * 48271) % 2147483647) / 2147483647;
  for (let i = 0; i < 2000; i++) {
    const v = () => (rand() * 400 - 50).toPrecision(1 + Math.floor(rand() * 15));
    out.add(`hsl(${v()}, ${v()}%, ${v()}%)`).add(`rgb(${v()} ${v()} ${v()} / ${v()}%)`).add(`rgba(${v()}%, ${v()}%, ${v()}%, ${rand().toPrecision(3)})`);
  }
  return [...out];
}

function beyondInputs() {
  const out = [];
  for (const n of BEYOND) out.push(`rgb(${n}, 0, 0)`, `rgb(0% 0% ${n}%)`, `rgba(1, 2, 3, ${n})`, `hsl(200 70% ${n}%)`, `hsl(${n}, 50%, 50%)`);
  return out;
}

const same = (a, b) => Object.is(a, b) || (a === 0 && b === 0) || (Number.isNaN(a) && Number.isNaN(b));
const close = (a, b) => same(a, b) || Math.abs(a - b) <= 1e-15 * Math.max(Math.abs(a), Math.abs(b));
const differ = [];
let accepted = 0;
let approximate = 0;
function compare(s, eq) {
  const want = parseCssColor(s) ?? null;
  const got = color_parse(s)?.color ?? null;
  if (want) accepted++;
  const ok = want === null || got === null ? want === got : want.every((x, i) => eq(x, got[i]));
  if (!ok) differ.push({ input: s, maplibre: want, mbmap: got });
  return ok && want !== null && !want.every((x, i) => same(x, got[i]));
}
const all = inputs();
for (const s of all) compare(s, same);
const beyond = beyondInputs();
for (const s of beyond) if (compare(s, close)) approximate++;
for (const d of differ.slice(0, 20)) console.log(JSON.stringify(d));
console.log(`${all.length + beyond.length} inputs (${accepted} colors; ${beyond.length} past the fast path, ${approximate} of them within 1e-15 but not exact), ${differ.length} differ`);
await writeFile(path.join(ROOT, "bench/results/color-golden.json"),
  `${JSON.stringify({ inputs: all.length + beyond.length, colors: accepted, beyond: beyond.length, approximate, differ: differ.length, differences: differ.slice(0, 50) }, null, 2)}\n`);
process.exitCode = differ.length ? 1 : 0;
