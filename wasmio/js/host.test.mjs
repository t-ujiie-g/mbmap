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
