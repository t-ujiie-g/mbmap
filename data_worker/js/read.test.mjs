import assert from "node:assert/strict";
import test from "node:test";
import { dataImports, dbfEncoding, isZip } from "./read.mjs";

test("dbfEncoding takes the option, then the .cpg, then the language driver, then UTF-8", () => {
  for (const cpg of ["SJIS", "CP932", "ANSI 932", "Shift_JIS", "932\r\n", " windows-31j "]) assert.equal(dbfEncoding(undefined, cpg, null), "shift_jis");
  assert.equal(dbfEncoding(undefined, "UTF-8", null), "utf-8");
  assert.equal(dbfEncoding(undefined, "65001", null), "utf-8");
  assert.equal(dbfEncoding(undefined, "1252", null), "windows-1252");
  assert.equal(dbfEncoding(undefined, "CP1251", null), "windows-1251");
  assert.equal(dbfEncoding(undefined, "ISO-8859-1", null), "windows-1252");
  assert.equal(dbfEncoding(undefined, "28595", null), "iso-8859-5");
  assert.equal(dbfEncoding(undefined, "EUC-JP", null), "euc-jp");
  assert.equal(dbfEncoding("cp936", "UTF-8", null), "gbk");
  const ldid = (b) => Object.assign(new Uint8Array(32), { 29: b });
  assert.equal(dbfEncoding(undefined, undefined, ldid(0x13)), "shift_jis");
  assert.equal(dbfEncoding(undefined, "nonsense", ldid(0x7b)), "shift_jis");
  assert.equal(dbfEncoding(undefined, undefined, ldid(0x57)), "utf-8");
  assert.equal(dbfEncoding(undefined, "437", ldid(0)), "utf-8");
});

test("isZip tells archives by their first bytes", () => {
  assert.equal(isZip(Uint8Array.of(0x50, 0x4b, 3, 4)), true);
  assert.equal(isZip(Uint8Array.of(0x50, 0x4b, 5, 6)), true);
  assert.equal(isZip(Uint8Array.of(0, 0, 0x27, 0x0a)), false);
  assert.equal(isZip(Uint8Array.of(0x50, 0x4b)), false);
});

test("dataImports decodes DBF text in the decoder it is given, NULs removed and trimmed", () => {
  const memory = { buffer: new Uint8Array([0x20, 0x92, 0x6e, 0x00, 0x90, 0x7d, 0x20]).buffer };
  const { host } = dataImports(() => memory);
  host.decoder = new TextDecoder("shift_jis");
  const n = host.decode(0, 7);
  assert.equal(String.fromCharCode(...Array.from({ length: n }, (_, i) => host.text_code(i))), "地図");
});
