import assert from "node:assert/strict";
import test from "node:test";
import { packPattern } from "../src/relate-pattern.ts";

test("packPattern packs three bits a cell, first cell lowest, in any case", () => {
  assert.equal(packPattern("T*F**FFF*"), packPattern("t*f**fff*"));
  const p = packPattern("T*F**FFF*");
  assert.deepEqual([...Array(9).keys()].map((k) => "F012T*"[(p >> (k * 3)) & 7]).join(""), "T*F**FFF*");
  assert.equal(packPattern("0FFFFFFF2") & 7, 1);
});

test("packPattern refuses malformed patterns and those disjoint features match", () => {
  assert.throws(() => packPattern("T*F**FFF"), /not a DE-9IM pattern/);
  assert.throws(() => packPattern("T*F**FFFX"), /not a DE-9IM pattern/);
  assert.throws(() => packPattern("FF*FF****"), /disjoint features match/);
  assert.throws(() => packPattern("*********"), /disjoint features match/);
});
