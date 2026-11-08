import { test } from "node:test";
import assert from "node:assert/strict";
import { tilesetSubset } from "./tileset-subset.mjs";

const R = Math.PI / 180;
const region = (w, s, e, n) => ({ region: [w * R, s * R, e * R, n * R, 0, 100] });

test("tilesetSubset keeps tiles meeting the box and their ancestors only", () => {
  const tileset = {
    root: {
      boundingVolume: region(139, 35, 141, 37),
      children: [
        { boundingVolume: region(139, 35, 140, 36), content: { uri: "data/a.b3dm" },
          children: [
            { boundingVolume: region(139.5, 35.5, 139.6, 35.6), content: { uri: "data/b.b3dm" } },
            { boundingVolume: region(139.0, 35.0, 139.1, 35.1), content: { uri: "data/c.b3dm" } },
          ] },
        { boundingVolume: region(140, 36, 141, 37), content: { uri: "data/d.b3dm" } },
      ],
    },
  };
  assert.deepEqual(tilesetSubset(tileset, [139.55, 35.55, 139.56, 35.56]), ["data/a.b3dm", "data/b.b3dm"]);
});

test("tilesetSubset refuses content paths that leave the tileset's directory", () => {
  for (const uri of ["../x.b3dm", "/x.b3dm", "https://e.com/x.b3dm", "data/../../x.b3dm", "sub.json"])
    assert.throws(() => tilesetSubset({ root: { boundingVolume: region(0, 0, 1, 1), content: { uri } } }, [0, 0, 1, 1]));
});
