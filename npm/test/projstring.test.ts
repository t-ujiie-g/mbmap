import assert from "node:assert/strict";
import test from "node:test";
import { parseProjString } from "../src/projstring.ts";

const D2R = 0.01745329251994329577;

test("a PROJ string is parsed as proj4js reads it", () => {
  const s = parseProjString("+proj=lcc +lat_0=46.5 +lon_0=3 +lat_1=49 +lat_2=44 +x_0=700000 +y_0=6600000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs +type=crs");
  assert.equal(s.length, 34);
  assert.equal(s[0], 4); // lcc
  assert.equal(s[1], 6378137);
  assert.equal(s[2], (1 - 1 / 298.257222101) * 6378137);
  assert.equal(s[4], 7);
  assert.deepEqual(Array.from(s.slice(5, 12)), [0, 0, 0, 0, 0, 0, 0]);
  assert.equal(s[16], 46.5 * D2R);
  assert.equal(s[17], 49 * D2R);
  assert.equal(s[18], 44 * D2R);
  assert.equal(s[20], 3 * D2R);
  assert.equal(s[26], 700000);
  assert.equal(s[27], 6600000);
  assert.ok(Number.isNaN(s[13]) && Number.isNaN(s[28]) && Number.isNaN(s[29]));
});

test("datums, ellipsoids, units and prime meridians come from proj4js's tables", () => {
  const osgb = parseProjString("+proj=tmerc +lat_0=49 +lon_0=-2 +k=0.9996012717 +x_0=400000 +y_0=-100000 +datum=OSGB36 +units=ft");
  assert.deepEqual([osgb[1], osgb[2]], [6377563.396, 6356256.91]);
  assert.deepEqual(Array.from(osgb.slice(4, 12)), [7, 446.448, -125.157, 542.06, 0.1502, 0.247, 0.8421, -20.4894]);
  assert.equal(osgb[13], 0.3048);
  assert.equal(osgb[28], 0.9996012717);
  const wgs = parseProjString("+proj=utm +zone=54 +south +datum=WGS84");
  assert.deepEqual([wgs[0], wgs[4], wgs[12], wgs[29], wgs[30]], [3, 3, 1, 54, 1]);
  // Only "+datum=WGS84" spelled so counts as WGS 84 for proj4js's datum shortcut.
  assert.equal(parseProjString("+proj=longlat +datum=wgs84")[12], 0);
  const sphere = parseProjString("+proj=merc +a=6378137 +b=6378137 +nadgrids=@null");
  assert.deepEqual([sphere[1], sphere[2], sphere[4]], [6378137, 6378137, 0]);
  assert.equal(parseProjString("+proj=longlat +R=6371000")[2], 6371000);
  assert.equal(parseProjString("+proj=longlat +ellps=bessel +pm=paris")[14], 2.337229166667 * D2R);
  assert.equal(parseProjString("+proj=longlat +ellps=intl +pm=-1.5")[14], -1.5 * D2R);
  assert.equal(parseProjString("+proj=latlong")[0], 0);
  assert.equal(parseProjString("+proj=omerc +no_off +no_rot +lat_0=4 +lonc=115 +alpha=53.3")[31], 1);
});

test("what the analysis module cannot do is refused", () => {
  assert.throws(() => parseProjString("+proj=geos +h=35785831"), /unsupported projection: \+proj=geos/);
  assert.throws(() => parseProjString("+proj=tmerc +nadgrids=tky2jgd.gsb"), /grid shifts/);
  assert.throws(() => parseProjString("+proj=longlat +datum=NAD27"), /grid shifts/);
  assert.throws(() => parseProjString("+proj=longlat +towgs84=1,2"), /3 or 7 values/);
  assert.throws(() => parseProjString("+proj=tmerc +lat_0=north"), /\+lat_0: not a number/);
  assert.throws(() => parseProjString("+proj=utm +zone=61"), /not a UTM zone/);
  assert.throws(() => parseProjString("+proj=longlat +towgs84=1,2,x"), /not a number/);
});
