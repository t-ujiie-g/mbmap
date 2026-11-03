import assert from "node:assert/strict";
import test from "node:test";
import { hostNumber, hostText } from "./host.mjs";

test("hostNumber reads the number at an address with Number()", () => {
  const memory = { buffer: new ArrayBuffer(64) };
  const bytes = new Uint8Array(memory.buffer);
  const text = "-1.2345678901234567e-300";
  bytes.set([...text].map((c) => c.charCodeAt(0)), 8);
  const number = hostNumber(() => memory);
  assert.equal(number(8, text.length), -1.2345678901234567e-300);
  assert.equal(number(8, 2), -1);
});

test("hostNumber renews its view when memory grows, and reads non-numbers as NaN", () => {
  let memory = { buffer: new ArrayBuffer(4) };
  const number = hostNumber(() => memory);
  new Uint8Array(memory.buffer).set([0x34, 0x32]);
  assert.equal(number(0, 2), 42);
  memory = { buffer: new ArrayBuffer(16) };
  new Uint8Array(memory.buffer).set([0x31, 0x65, 0x33], 10);
  assert.equal(number(10, 3), 1000);
  new Uint8Array(memory.buffer).set([0x78], 10);
  assert.ok(Number.isNaN(number(10, 1)));
});

test("hostText builds a number from code units and gives String(x) unit by unit", () => {
  const t = hostText();
  for (const c of "6.02e23") t.text_char(c.charCodeAt(0));
  assert.equal(t.text_number(), 6.02e23);
  assert.equal(t.text_number(), 0);
  const n = t.number_text(1 / 3);
  const s = Array.from({ length: n }, (_, i) => String.fromCharCode(t.text_code(i))).join("");
  assert.equal(s, String(1 / 3));
  assert.equal(t.number_text(1e21), 5);
});

test("hostText's intl formats numbers, compares and resolves locales as Intl does", () => {
  const t = hostText();
  const push = (...parts) => parts.forEach((s) => [...s].forEach((c) => t.text_char(c.charCodeAt(0))));
  const read = (n) => Array.from({ length: n }, (_, i) => String.fromCharCode(t.text_code(i))).join("");
  push("de-DE", "EUR");
  const euro = new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR", maximumFractionDigits: 1 });
  assert.equal(read(t.intl(0, 1 | 2 | 16, 1234.5, 0, 1, 5, 3)), euro.format(1234.5));
  push("meter");
  assert.equal(read(t.intl(0, 4, 12, 0, 0, 0, 0)), new Intl.NumberFormat([], { style: "unit", unit: "meter" }).format(12));
  push("XYZ1");
  assert.equal(t.intl(0, 2, 1, 0, 0, 0, 4), -1);
  push("abc", "ABC");
  assert.equal(t.intl(1, 0, 0, 0, 0, 3, 3), 0);
  push("abc", "ABC");
  assert.notEqual(t.intl(1, 1, 0, 0, 0, 3, 3), 0);
  push("a", "b", "not a locale!");
  assert.ok(Number.isNaN(t.intl(1, 4, 0, 0, 0, 1, 1)));
  push("ja-JP");
  assert.equal(read(t.intl(2, 1, 0, 0, 0, 5, 0)), new Intl.Collator("ja-JP").resolvedOptions().locale);
});
