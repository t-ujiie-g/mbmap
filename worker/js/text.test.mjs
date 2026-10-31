import assert from "node:assert/strict";
import test from "node:test";
import { layoutLabel, SDF_BUFFER, SDF_SIZE } from "./text.mjs";

// Every glyph is a full em: an ideograph's ink fills its box, a space has none.
const metrics = (cp) => ({
  advance: SDF_SIZE,
  left: -SDF_BUFFER,
  top: SDF_SIZE * 0.88 + SDF_BUFFER,
  width: cp === 32 ? 0 : SDF_SIZE + 2 * SDF_BUFFER,
  height: cp === 32 ? 0 : SDF_SIZE + 2 * SDF_BUFFER,
});
const round = (xs) => xs.map((x) => Math.round(x * 100) / 100);

test("a centered line puts its em boxes around the anchor", () => {
  const { quads, box } = layoutLabel("東京駅", 10, { lineHeight: 1 }, metrics);
  assert.deepEqual(round(box), [-15, -5, 15, 5]);
  assert.deepEqual(quads.map((q) => q.cp), [..."東京駅"].map((c) => c.codePointAt(0)));
  // The ink box of the first glyph, padded by the SDF buffer.
  const pad = (SDF_BUFFER * 10) / SDF_SIZE;
  assert.deepEqual(round([quads[0].x0, quads[0].y0, quads[0].x1, quads[0].y1]), round([-15 - pad, -5 - pad, -5 + pad, 5 + pad]));
});

test("anchors and offsets move the box; the anchor side sets the justification", () => {
  assert.deepEqual(round(layoutLabel("ab", 10, { anchor: 5, lineHeight: 1 }, metrics).box), [0, 0, 20, 10]);
  assert.deepEqual(round(layoutLabel("ab", 10, { anchor: 8, lineHeight: 1 }, metrics).box), [-20, -10, 0, 0]);
  assert.deepEqual(round(layoutLabel("ab", 10, { offset: [1, -2], lineHeight: 1 }, metrics).box), [0, -25, 20, -15]);
  // Right anchored: the short second line ends where the first does.
  const { quads } = layoutLabel("abc\nd", 10, { anchor: 2, lineHeight: 1 }, metrics);
  assert.equal(Math.round(quads[3].x1 - quads[2].x1), 0);
});

test("lines break at spaces and between ideographs, not before closing marks", () => {
  const lines = (text, maxWidth) => {
    const { quads } = layoutLabel(text, 10, { maxWidth, lineHeight: 1 }, metrics);
    const rows = new Map();
    for (const q of quads) rows.set(Math.round(q.y0), (rows.get(Math.round(q.y0)) ?? "") + String.fromCodePoint(q.cp));
    return [...rows.values()];
  };
  assert.deepEqual(lines("aaa bbb", 4), ["aaa", "bbb"]);
  assert.deepEqual(lines("東京都千代田区", 4), ["東京都千", "代田区"]);
  assert.deepEqual(lines("南長崎（四）", 4), ["南長崎（四）"].flatMap((s) => [s.slice(0, 3), s.slice(3)]));
  assert.deepEqual(lines("あい。", 2), ["あ", "い。"]);
  assert.deepEqual(lines("abcdef", 2), ["abcdef"]);
});
