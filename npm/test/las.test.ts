import assert from "node:assert/strict";
import test from "node:test";
import { horizontalWkt, MAX_LAS_POINTS, MAX_LAS_VLRS, readLas, wktEpsg } from "../src/model/las.ts";
import { geoKeys, writeLas, wktRecord } from "../../bench/las/write.mjs";

const points = (n: number, rgb = true) =>
  Array.from({ length: n }, (_, i) => ({ x: i * 100, y: -i * 7, z: 3 * i + 1, intensity: 1000 + i, returns: 1 | (2 << 3), classification: i % 20, flags: i % 8, rgb: rgb ? [i * 300, 255 - i, i] : undefined }));

test("readLas reads a LAS 1.2 file of format 3: positions scaled and offset, colors, intensity, classes", () => {
  const bytes = writeLas({ minor: 2, format: 3, points: points(5), scale: [0.001, 0.01, 0.1], offset: [-50, 1000.5, 2] });
  const cloud = readLas(bytes, 100);
  assert.equal(cloud.version, "1.2");
  assert.equal(cloud.pointFormat, 3);
  assert.equal(cloud.count, 5);
  assert.equal(cloud.kept, 5);
  assert.deepEqual(cloud.scale, [0.001, 0.01, 0.1]);
  assert.deepEqual(cloud.offset, [-50, 1000.5, 2]);
  assert.deepEqual(Array.from(cloud.positions.subarray(3, 6)), [100 * 0.001 - 50, -7 * 0.01 + 1000.5, 4 * 0.1 + 2]);
  assert.deepEqual(cloud.min, [-50, -28 * 0.01 + 1000.5, 0.1 + 2]);
  assert.deepEqual(cloud.max, [400 * 0.001 - 50, 1000.5, 13 * 0.1 + 2]);
  assert.deepEqual(Array.from(cloud.intensity), [1000, 1001, 1002, 1003, 1004]);
  assert.deepEqual(Array.from(cloud.classification), [0, 1, 2, 3, 4]);
  assert.deepEqual(Array.from(cloud.returnNumber), [1, 1, 1, 1, 1]);
  assert.deepEqual(Array.from(cloud.numberOfReturns), [2, 2, 2, 2, 2]);
  assert.deepEqual(Array.from(cloud.colors!.subarray(0, 6)), [0, 255 >> 8, 0, 300 >> 8, 254 >> 8, 0]);
  assert.equal(cloud.crs, null);
});

test("readLas keeps 8-bit colors stored in 16 bits as they are", () => {
  const cloud = readLas(writeLas({ minor: 0, format: 2, points: points(3).map((p, i) => ({ ...p, rgb: [10, 200 + i, 255] })) }), 10);
  assert.deepEqual(Array.from(cloud.colors!), [10, 200, 255, 10, 201, 255, 10, 202, 255]);
  assert.equal(readLas(writeLas({ minor: 1, format: 1, points: points(2) }), 10).colors, null);
});

test("readLas reads LAS 1.4 formats 6 to 10: the class byte, 4-bit returns, 64-bit counts", () => {
  for (const format of [6, 7, 8, 9, 10]) {
    const ps = points(4).map((p, i) => ({ ...p, classification: 64 + i, returns: 3 | (5 << 4) }));
    const cloud = readLas(writeLas({ minor: 4, format, points: ps }), 10);
    assert.equal(cloud.count, 4);
    assert.deepEqual(Array.from(cloud.classification), [64, 65, 66, 67]);
    assert.deepEqual(Array.from(cloud.returnNumber), [3, 3, 3, 3]);
    assert.deepEqual(Array.from(cloud.numberOfReturns), [5, 5, 5, 5]);
    assert.equal(cloud.colors !== null, [7, 8, 10].includes(format));
  }
});

test("readLas skips extra bytes after each record and reads formats 4 and 5 of LAS 1.3", () => {
  for (const format of [4, 5]) {
    const cloud = readLas(writeLas({ minor: 3, format, points: points(3), extra: 7 }), 10);
    assert.deepEqual(Array.from(cloud.positions), [0, 0, 0.01, 1, -0.07, 0.04, 2, -0.14, 0.07]);
    assert.deepEqual(Array.from(cloud.intensity), [1000, 1001, 1002]);
  }
});

test("readLas thins to every k-th point from the first, k = ceil(count / maxPoints)", () => {
  const cloud = readLas(writeLas({ minor: 2, format: 0, points: points(10) }), 4);
  assert.equal(cloud.count, 10);
  assert.equal(cloud.kept, 4);
  assert.deepEqual(Array.from(cloud.intensity), [1000, 1003, 1006, 1009]);
  assert.equal(readLas(writeLas({ minor: 2, format: 0, points: points(10) }), 5).kept, 5);
});

test("readLas finds the CRS: GeoTIFF keys (projected before geographic) and the WKT when its bit is set", () => {
  const keyed = readLas(writeLas({ minor: 2, format: 0, points: points(1), vlrs: [geoKeys([[2048, 6668], [3072, 6677], [4096, 6697]])] }), 1);
  assert.deepEqual(keyed.crs, { epsg: 6677 });
  assert.deepEqual(readLas(writeLas({ minor: 2, format: 0, points: points(1), vlrs: [geoKeys([[2048, 4326]])] }), 1).crs, { epsg: 4326 });
  assert.equal(readLas(writeLas({ minor: 2, format: 0, points: points(1), vlrs: [geoKeys([[3072, 32767]])] }), 1).crs, null);
  const wkt = 'PROJCS["JGD2011 / Japan Plane Rectangular CS IX",GEOGCS["JGD2011",AUTHORITY["EPSG","6668"]],AUTHORITY["EPSG","6677"]]';
  const both = { minor: 4, format: 6, points: points(1), vlrs: [geoKeys([[3072, 2451]])], evlrs: [wktRecord(wkt)] };
  assert.deepEqual(readLas(writeLas({ ...both, globalEncoding: 16 }), 1).crs, { epsg: 6677, wkt });
  assert.deepEqual(readLas(writeLas(both), 1).crs, { epsg: 2451 });
  const bare = 'GEOGCS["somewhere",DATUM["x",SPHEROID["y",6378137,298.257,AUTHORITY["EPSG","7030"]]]]';
  assert.deepEqual(readLas(writeLas({ minor: 3, format: 0, points: points(1), vlrs: [wktRecord(bare)], globalEncoding: 16 }), 1).crs, { wkt: bare });
});

test("wktEpsg takes only the outermost element's authority, WKT1 or WKT2", () => {
  assert.equal(wktEpsg('GEOGCS["a",DATUM["b",AUTHORITY["EPSG","6152"]],AUTHORITY["EPSG","4152"]]'), 4152);
  assert.equal(wktEpsg('PROJCRS["a",BASEGEOGCRS["b",ID["EPSG",4612]],ID["EPSG",2451]]'), 2451);
  assert.equal(wktEpsg('GEOGCS["AUTHORITY[\\"EPSG\\",\\"1\\"]",DATUM["b",AUTHORITY["EPSG","6152"]]]'), undefined);
});

test("horizontalWkt takes a compound CRS's first element, and readLas its EPSG code", () => {
  const horizontal = 'PROJCS["JGD2011 / IX",GEOGCS["JGD2011",AUTHORITY["EPSG","6668"]],AUTHORITY["EPSG","6677"]]';
  const compound = `COMPD_CS["JGD2011 + JGD2011 height",${horizontal},VERT_CS["JGD2011 height",AUTHORITY["EPSG","6695"]],AUTHORITY["EPSG","10162"]]`;
  assert.equal(horizontalWkt(compound), horizontal);
  assert.equal(horizontalWkt(horizontal), horizontal);
  assert.equal(horizontalWkt('COMPOUNDCRS["a",PROJCRS["b",ID["EPSG",2451]],VERTCRS["c"]]'), 'PROJCRS["b",ID["EPSG",2451]]');
  const cloud = readLas(writeLas({ minor: 4, format: 6, points: points(1), vlrs: [wktRecord(compound)], globalEncoding: 16 }), 1);
  assert.deepEqual(cloud.crs, { epsg: 6677, wkt: compound });
});

test("readLas refuses LAZ, unknown versions and formats, and files that point past their end", () => {
  const good = writeLas({ minor: 2, format: 1, points: points(3) });
  const changed = (f: (b: Uint8Array, v: DataView) => void, bytes = good) => {
    const b = bytes.slice();
    f(b, new DataView(b.buffer));
    return b;
  };
  const refuses = (b: Uint8Array, re: RegExp, max = 10) => assert.throws(() => readLas(b, max), re);
  refuses(changed((b) => (b[104] |= 0x80)), /LAZ/);
  refuses(writeLas({ minor: 2, format: 1, points: points(1), vlrs: [{ userId: "laszip encoded", recordId: 22204, data: new Uint8Array(34) }] }), /LAZ/);
  refuses(changed((b) => (b[0] = 0)), /not a LAS file/);
  refuses(good.subarray(0, 100), /not a LAS file/);
  refuses(changed((b) => (b[25] = 5)), /version 1\.5/);
  refuses(changed((b) => (b[24] = 2)), /version 2\.2/);
  refuses(changed((b) => (b[104] = 11)), /format 11/);
  refuses(changed((b, v) => v.setUint16(105, 20, true)), /record length 20/);
  refuses(changed((b, v) => v.setUint16(94, 200, true)), /header size/);
  refuses(changed((b, v) => v.setUint16(94, 235, true)), /point data inside the header/);
  refuses(changed((b, v) => v.setUint32(107, 4, true)), /beyond the file/);
  refuses(changed((b, v) => v.setUint32(96, 0xffffff00, true)), /beyond the file/);
  refuses(changed((b, v) => v.setFloat64(131, NaN, true)), /finite/);
  refuses(changed((b, v) => v.setUint32(100, 3, true)), /VLR \d+ (data )?beyond the file/);
  refuses(changed((b, v) => v.setUint32(100, MAX_LAS_VLRS + 1, true)), /more than 4096 VLRs/);
  const v14 = writeLas({ minor: 4, format: 6, points: points(2), evlrs: [wktRecord("GEOGCS[]")] });
  refuses(changed((b, v) => v.setBigUint64(235, 1n << 40n, true), v14), /EVLRs beyond the file/);
  refuses(changed((b, v) => v.setBigUint64(247, 1n << 60n, true), v14), /point count out of range/);
  refuses(changed((b, v) => v.setBigUint64(247, 1n << 40n, true), v14), /beyond the file/);
  refuses(changed((b, v) => v.setBigUint64(v14.length - 9 - 60 + 20, 1n << 40n, true), v14), /EVLR 0 data beyond the file/);
  refuses(good, /maxPoints/, 0);
  refuses(good, /maxPoints/, 1.5);
  assert.equal(MAX_LAS_POINTS, 10_000_000);
});
