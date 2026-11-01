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
// A quad's bounds as [x0, y0, x1, y1].
const bounds = (q) => [Math.min(...q.corners.map((c) => c[0])), Math.min(...q.corners.map((c) => c[1])),
  Math.max(...q.corners.map((c) => c[0])), Math.max(...q.corners.map((c) => c[1]))];

test("a centered line puts its em boxes around the anchor", () => {
  const { quads, box } = layoutLabel("東京駅", 10, { lineHeight: 1 }, metrics);
  assert.deepEqual(round(box), [-15, -5, 15, 5]);
  assert.deepEqual(quads.map((q) => q.cp), [..."東京駅"].map((c) => c.codePointAt(0)));
  // The ink box of the first glyph, padded by the SDF buffer.
  const pad = (SDF_BUFFER * 10) / SDF_SIZE;
  assert.deepEqual(round(bounds(quads[0])), round([-15 - pad, -5 - pad, -5 + pad, 5 + pad]));
});

test("anchors and offsets move the box; the anchor side sets the justification", () => {
  assert.deepEqual(round(layoutLabel("ab", 10, { anchor: 5, lineHeight: 1 }, metrics).box), [0, 0, 20, 10]);
  assert.deepEqual(round(layoutLabel("ab", 10, { anchor: 8, lineHeight: 1 }, metrics).box), [-20, -10, 0, 0]);
  assert.deepEqual(round(layoutLabel("ab", 10, { offset: [1, -2], lineHeight: 1 }, metrics).box), [0, -25, 20, -15]);
  // Right anchored: the short second line ends where the first does.
  const { quads } = layoutLabel("abc\nd", 10, { anchor: 2, lineHeight: 1 }, metrics);
  assert.equal(Math.round(bounds(quads[3])[2] - bounds(quads[2])[2]), 0);
});

test("lines break at spaces and between ideographs, not before closing marks", () => {
  const lines = (text, maxWidth) => {
    const { quads } = layoutLabel(text, 10, { maxWidth, lineHeight: 1 }, metrics);
    const rows = new Map();
    for (const q of quads) rows.set(Math.round(bounds(q)[1]), (rows.get(Math.round(bounds(q)[1])) ?? "") + String.fromCodePoint(q.cp));
    return [...rows.values()];
  };
  assert.deepEqual(lines("aaa bbb", 4), ["aaa", "bbb"]);
  assert.deepEqual(lines("東京都千代田区", 4), ["東京都千", "代田区"]);
  assert.deepEqual(lines("南長崎（四）", 4), ["南長崎（四）"].flatMap((s) => [s.slice(0, 3), s.slice(3)]));
  assert.deepEqual(lines("あい。", 2), ["あ", "い。"]);
  assert.deepEqual(lines("abcdef", 2), ["abcdef"]);
});

test("vertical text stacks upright ideographs in columns from the right", () => {
  const { quads, box } = layoutLabel("東京\n駅", 10, { vertical: true, lineHeight: 1 }, metrics);
  assert.deepEqual(round(box), [-10, -10, 10, 10]);
  const centers = quads.map((q) => round([(bounds(q)[0] + bounds(q)[2]) / 2, (bounds(q)[1] + bounds(q)[3]) / 2]));
  // 東 above 京 in the right column; 駅, centered, in the left one.
  assert.deepEqual(centers, [[5, -5], [5, 5], [-5, 0]]);
});

test("vertical text turns Latin sideways and punctuation to its vertical forms", () => {
  const { quads } = layoutLabel("南（A）", 10, { vertical: true, lineHeight: 1 }, metrics);
  // The brackets next to a sideways letter keep their forms; alone they turn.
  assert.deepEqual(quads.map((q) => String.fromCodePoint(q.cp)).join(""), "南（A）");
  const turned = layoutLabel("南（北）", 10, { vertical: true, lineHeight: 1 }, metrics).quads;
  assert.deepEqual(turned.map((q) => String.fromCodePoint(q.cp)).join(""), "南︵北︶");
  // A sideways glyph's corners turn a quarter: its first corner is top-right.
  const a = quads[2];
  assert.ok(a.corners[0][0] > a.corners[3][0] && a.corners[0][1] < a.corners[1][1]);
  // Text without upright characters stays horizontal.
  assert.equal(round(layoutLabel("AB", 10, { vertical: true, lineHeight: 1 }, metrics).box)[2], 10);
});
