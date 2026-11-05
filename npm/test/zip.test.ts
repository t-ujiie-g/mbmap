import assert from "node:assert/strict";
import test from "node:test";
import { crc32, deflateRawSync } from "node:zlib";
import { readZip } from "../src/zip.ts";

interface File {
  name: string | Uint8Array;
  data: Uint8Array;
  method?: number;
  flags?: number;
  size?: number;
}

// A zip archive of `files` (deflated unless `method` 0); `size` lies about the inflated size.
function zip(files: File[], end: (v: DataView) => void = () => {}): Uint8Array {
  const parts: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;
  for (const f of files) {
    const method = f.method ?? 8;
    const data = method === 8 ? new Uint8Array(deflateRawSync(f.data)) : f.data;
    const name = typeof f.name === "string" ? new TextEncoder().encode(f.name) : f.name;
    const fields = (v: DataView, at: number) => {
      v.setUint16(at, f.flags ?? 0x800, true);
      v.setUint16(at + 2, method, true);
      v.setUint32(at + 8, crc32(f.data), true);
      v.setUint32(at + 12, data.length, true);
      v.setUint32(at + 16, f.size ?? f.data.length, true);
      v.setUint16(at + 20, name.length, true);
    };
    const local = new Uint8Array(30 + name.length);
    const lv = new DataView(local.buffer);
    lv.setUint32(0, 0x04034b50, true);
    fields(lv, 6);
    local.set(name, 30);
    const c = new Uint8Array(46 + name.length);
    const cv = new DataView(c.buffer);
    cv.setUint32(0, 0x02014b50, true);
    fields(cv, 8);
    cv.setUint32(42, offset, true);
    c.set(name, 46);
    parts.push(local, data);
    central.push(c);
    offset += local.length + data.length;
  }
  const size = central.reduce((s, c) => s + c.length, 0);
  const e = new Uint8Array(22);
  const ev = new DataView(e.buffer);
  ev.setUint32(0, 0x06054b50, true);
  ev.setUint16(8, files.length, true);
  ev.setUint16(10, files.length, true);
  ev.setUint32(12, size, true);
  ev.setUint32(16, offset, true);
  end(ev);
  const all = [...parts, ...central, e];
  const out = new Uint8Array(all.reduce((s, p) => s + p.length, 0));
  all.reduce((at, p) => (out.set(p, at), at + p.length), 0);
  return out;
}

const bytes = (s: string) => new TextEncoder().encode(s);

test("readZip lists entries (directories left out) and reads stored and deflated ones", async () => {
  const text = bytes("地図".repeat(1000));
  const z = readZip(zip([{ name: "a/", data: new Uint8Array(0), method: 0 }, { name: "a/地図.txt", data: text }, { name: "b.bin", data: bytes("xyz"), method: 0 }]));
  assert.deepEqual(z.entries.map((e) => [e.name, e.size]), [["a/地図.txt", text.length], ["b.bin", 3]]);
  assert.deepEqual(await z.read(z.entries[0]), text);
  assert.deepEqual(await z.read(z.entries[1]), bytes("xyz"));
});

test("readZip decodes names without the UTF-8 flag as UTF-8 if valid, else Shift_JIS", () => {
  const sjis = Uint8Array.of(0x92, 0x6e, 0x90, 0x7d, 0x2e, 0x73, 0x68, 0x70);
  const z = readZip(zip([{ name: sjis, data: bytes("x"), flags: 0 }, { name: "名前.shp", data: bytes("y"), flags: 0 }]));
  assert.deepEqual(z.entries.map((e) => e.name), ["地図.shp", "名前.shp"]);
});

test("readZip refuses what it does not read", async () => {
  const one = [{ name: "a", data: bytes("abc") }];
  assert.throws(() => readZip(bytes("PK\x03\x04 no end")), /not a zip archive/);
  assert.throws(() => readZip(zip(one, (v) => v.setUint16(10, 0xffff, true))), /ZIP64/);
  assert.throws(() => readZip(zip(one, (v) => v.setUint16(4, 1, true))), /split archives/);
  assert.throws(() => readZip(zip([...one, ...one]), { entries: 1 }), /more than 1 entries/);
  assert.throws(() => readZip(zip(one, (v) => v.setUint32(16, 3, true))), /malformed central directory/);
  const read = (files: File[], limits = {}) => {
    const z = readZip(zip(files), limits);
    return z.read(z.entries[0]);
  };
  await assert.rejects(read([{ ...one[0], flags: 0x801 }]), /encrypted/);
  await assert.rejects(read([{ ...one[0], method: 12 }]), /method 12/);
  await assert.rejects(read([{ ...one[0], size: 0xffffffff }]), /ZIP64/);
  await assert.rejects(read(one, { bytes: 2 }), /inflates to more than 2 bytes/);
  await assert.rejects(read([{ ...one[0], size: 2 }]), /inflates past/);
  await assert.rejects(read([{ ...one[0], size: 5 }]), /inflates short/);
  await assert.rejects(read([{ ...one[0], method: 0, size: 2 }]), /stored entry of the wrong size/);
  const broken = zip(one);
  broken[0] = 0;
  const z = readZip(broken);
  await assert.rejects(z.read(z.entries[0]), /malformed local header/);
  await assert.rejects(z.read({ name: "a", size: 3 }), /not an entry/);
  // Deflate data that is not deflate.
  const garbage = zip([{ name: "a", data: bytes("abc"), method: 0 }]);
  new DataView(garbage.buffer).setUint16(8, 8, true);
  const central = garbage.length - 22 - 47;
  new DataView(garbage.buffer).setUint16(central + 10, 8, true);
  const g = readZip(garbage);
  await assert.rejects(g.read(g.entries[0]), /invalid deflate data|inflates/);
  // A cap holds across reads.
  const two = readZip(zip([...one, { name: "b", data: bytes("def") }]), { bytes: 4 });
  await two.read(two.entries[0]);
  await assert.rejects(two.read(two.entries[1]), /inflates to more than 4 bytes/);
});
