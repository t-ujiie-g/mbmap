// Writing SLPKs as Esri's tools do, for the SLPK golden and the pack test's synthetic SLPK
// (`node i3s/slpk-write.mjs` writes bench/npm/pages/i3s/set.slpk from the synthetic layer).
import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { crc32, deflateRawSync, gzipSync } from "node:zlib";
import { md5 } from "../../npm/src/i3s/slpk.ts";
import { ROOT } from "../lib/root.mjs";

/** A layer's resources as REST paths (`layer`, `nodepages/0`, `nodes/1/geometries/0`, …) to their bytes, later directories adding to the first. */
export async function resources(dirs) {
  const out = new Map();
  for (const dir of dirs) {
    const walk = async (d) => {
      for (const e of await readdir(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) await walk(p);
        else {
          const rest = path.relative(dir, p).split(path.sep).join("/");
          out.set(rest === "layer.json" ? "layer" : rest, new Uint8Array(await readFile(p)));
        }
      }
    };
    await walk(dir);
  }
  return out;
}

const isJpeg = (b) => b[0] === 0xff && b[1] === 0xd8;
const isPng = (b) => b[0] === 0x89 && b[1] === 0x50;

/** The SLPK entry a REST path is packed as, and its bytes: gzipped but for JPEG and PNG textures. */
export function entryOf(rest, bytes) {
  const gz = (name) => [name, new Uint8Array(gzipSync(bytes))];
  if (rest === "layer") return gz("3dSceneLayer.json.gz");
  if (/^nodepages\/\d+$/.test(rest)) return gz(`${rest}.json.gz`);
  if (/\/textures\//.test(rest)) return isJpeg(bytes) ? [`${rest}.jpg`, bytes] : isPng(bytes) ? [`${rest}.png`, bytes] : gz(`${rest}.bin.dds.gz`);
  return gz(`${rest}.bin.gz`);
}

const le = (n, v) => {
  const b = Buffer.alloc(n);
  if (n === 2) b.writeUInt16LE(v);
  else if (n === 4) b.writeUInt32LE(v >>> 0);
  else b.writeBigUInt64LE(BigInt(v));
  return b;
};

/** A zip of `entries` ([name, bytes]) as Esri's tools write SLPKs: stored (deflated with `deflate`), zip64 fields with `zip64`, the hash table last with `hash`. */
export function writeSlpk(entries, { zip64 = false, hash = true, deflate = false } = {}) {
  const parts = [];
  const central = [];
  const offsets = [];
  let offset = 0;
  const add = (name, data, method) => {
    const stored = method === 8 ? deflateRawSync(data) : data;
    const n = Buffer.from(name);
    const lx = zip64 ? Buffer.concat([le(2, 1), le(2, 16), le(8, data.length), le(8, stored.length)]) : Buffer.alloc(0);
    const cx = zip64 ? Buffer.concat([le(2, 1), le(2, 24), le(8, data.length), le(8, stored.length), le(8, offset)]) : Buffer.alloc(0);
    const sizes = zip64 ? [le(4, 0xffffffff), le(4, 0xffffffff)] : [le(4, stored.length), le(4, data.length)];
    const common = [le(2, 0), le(2, method), le(4, 0), le(4, crc32(data)), ...sizes, le(2, n.length)];
    const local = Buffer.concat([le(4, 0x04034b50), le(2, 45), ...common, le(2, lx.length), n, lx, stored]);
    central.push(Buffer.concat([le(4, 0x02014b50), le(2, 45), le(2, 45), ...common, le(2, cx.length), le(2, 0), le(2, 0), le(2, 0), le(4, 0), le(4, zip64 ? 0xffffffff : offset), n, cx]));
    offsets.push([name, offset]);
    parts.push(local);
    offset += local.length;
  };
  for (const [name, data] of entries) add(name, data, deflate ? 8 : 0);
  if (hash) {
    // loaders.gl's composeHashFile: lowercase names but 3dSceneLayer.json.gz, sorted as two little-endian u64s.
    const rows = offsets.map(([name, at]) => Buffer.concat([md5(Buffer.from(name === "3dSceneLayer.json.gz" ? name : name.toLowerCase())), le(8, at)]));
    rows.sort((a, b) => {
      const c = a.readBigUInt64LE(0) - b.readBigUInt64LE(0) || a.readBigUInt64LE(8) - b.readBigUInt64LE(8);
      return c < 0n ? -1 : c > 0n ? 1 : 0;
    });
    add("@specialIndexFileHASH128@", Buffer.concat(rows), 0);
  }
  const dir = Buffer.concat(central);
  const tail = [];
  if (zip64) {
    const record = offset + dir.length;
    tail.push(Buffer.concat([le(4, 0x06064b50), le(8, 44), le(2, 45), le(2, 45), le(4, 0), le(4, 0), le(8, central.length), le(8, central.length), le(8, dir.length), le(8, offset)]));
    tail.push(Buffer.concat([le(4, 0x07064b50), le(4, 0), le(8, record), le(4, 1)]));
  }
  const count = zip64 ? 0xffff : central.length;
  tail.push(Buffer.concat([le(4, 0x06054b50), le(2, 0), le(2, 0), le(2, count), le(2, count), le(4, zip64 ? 0xffffffff : dir.length), le(4, zip64 ? 0xffffffff : offset), le(2, 0)]));
  return new Uint8Array(Buffer.concat([...parts, dir, ...tail]));
}


if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const files = await resources([path.join(ROOT, "bench/npm/pages/i3s/set/layers/0")]);
  const out = path.join(ROOT, "bench/npm/pages/i3s/set.slpk");
  await writeFile(out, writeSlpk([...files].map(([rest, bytes]) => entryOf(rest, bytes))));
  console.log(`wrote ${out}`);
}
