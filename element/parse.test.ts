import assert from "node:assert/strict";
import test from "node:test";
import { MAX_PITCH, MAX_ZOOM, parseBearing, parseCenter, parsePitch, parseWorkerCount, parseZoom } from "./parse.ts";

test("center is two in-range decimals", () => {
  assert.deepEqual(parseCenter("139.7671,35.6812"), { lng: 139.7671, lat: 35.6812 });
  assert.deepEqual(parseCenter(" -180 , 90 "), { lng: -180, lat: 90 });
  for (const bad of ["", "1", "1,2,3", "181,0", "0,-91", "1e2,0", "0x10,0", "NaN,0", "Infinity,0", "1,,2", "a,b"]) {
    assert.equal(parseCenter(bad), null, bad);
  }
});

test("zoom is a decimal from 0 to MAX_ZOOM", () => {
  assert.equal(parseZoom("14.5"), 14.5);
  assert.equal(parseZoom(String(MAX_ZOOM)), MAX_ZOOM);
  for (const bad of ["", "-1", "23", "1e1", "Infinity", "NaN", "12px", " "]) {
    assert.equal(parseZoom(bad), null, bad);
  }
});

test("worker count is 0 to MAX_WORKERS", () => {
  assert.equal(parseWorkerCount("0"), 0);
  assert.equal(parseWorkerCount("4"), 4);
  for (const bad of ["5", "-1", "1.0", "", "01"]) {
    assert.equal(parseWorkerCount(bad), null, bad);
  }
});

test("bearing is any decimal; pitch is a decimal from 0 to MAX_PITCH", () => {
  assert.equal(parseBearing("-45.5"), -45.5);
  assert.equal(parseBearing("720"), 720);
  assert.equal(parsePitch("30"), 30);
  assert.equal(parsePitch(String(MAX_PITCH)), MAX_PITCH);
  for (const bad of ["", "1e1", "NaN", "Infinity", "10deg"]) assert.equal(parseBearing(bad), null, bad);
  for (const bad of ["", "-1", "61", "1e1", "NaN"]) assert.equal(parsePitch(bad), null, bad);
});
