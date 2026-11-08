import assert from "node:assert/strict";
import test from "node:test";
import { SUN_LIGHT_STOPS, sunDirection, sunPosition, timeOfDayLights } from "../src/sun.ts";

const at = (iso: string) => new Date(iso);

test("sunPosition gives suncalc 2.1.1's getPosition bit for bit", () => {
  // Values printed by suncalc 2.1.1's getPosition(date, lat, lng) in Node.
  assert.deepEqual(sunPosition(at("2013-03-05T00:00:00Z"), 30.5, 50.5), {
    azimuth: 36.94707507400062,
    altitude: -39.46550678343545,
  });
  assert.deepEqual(sunPosition(at("2026-06-21T03:00:00Z"), 139.77, 35.68), {
    azimuth: 198.21584231216275,
    altitude: 77.19959278765559,
  });
  assert.deepEqual(sunPosition(at("2026-03-20T12:00:00Z"), 0, 0), {
    azimuth: 91.31836001804277,
    altitude: 88.1332571811297,
  });
  assert.deepEqual(sunPosition(Date.parse("2026-03-20T12:00:00Z"), 0, 0), sunPosition(at("2026-03-20T12:00:00Z"), 0, 0));
});

test("sunPosition at the poles: the June sun 23.5° up at the north pole, the December sun at the south", () => {
  assert.deepEqual(sunPosition(at("2026-06-21T12:00:00Z"), 0, 90), {
    azimuth: 179.5399929216096,
    altitude: 23.476598437468404,
  });
  assert.deepEqual(sunPosition(at("2026-12-21T12:00:00Z"), 0, -90), {
    azimuth: 359.5202564946717,
    altitude: 23.475860518431706,
  });
  // suncalc adds the refraction at 0° (0.48°) to every altitude below the horizon.
  assert.ok(sunPosition(at("2026-12-21T12:00:00Z"), 0, 90).altitude < -22.9);
});

test("an invalid date gives NaN position and direction, and timeOfDayLights refuses it", () => {
  const p = sunPosition(new Date(Number.NaN), 0, 0);
  assert.ok(Number.isNaN(p.azimuth) && Number.isNaN(p.altitude));
  assert.ok(sunDirection(new Date("not a date"), 0, 0).every(Number.isNaN));
  assert.throws(() => timeOfDayLights(new Date(Number.NaN), 0, 0), RangeError);
});

test("sunDirection is the unit vector [east, north, up] of the azimuth and altitude", () => {
  const date = at("2026-06-21T03:00:00Z");
  const { azimuth, altitude } = sunPosition(date, 139.77, 35.68);
  const [e, n, u] = sunDirection(date, 139.77, 35.68);
  assert.ok(Math.abs(Math.hypot(e, n, u) - 1) < 1e-15);
  assert.ok(Math.abs(Math.asin(u) * (180 / Math.PI) - altitude) < 1e-12);
  assert.ok(Math.abs(((Math.atan2(e, n) * (180 / Math.PI) + 360) % 360) - azimuth) < 1e-12);
  // Tokyo at noon in June: high in the south, a little west.
  assert.ok(u > 0.97 && n < 0 && e < 0);
  // Sunrise on the equator at the equinox is in the east.
  const [e2, n2, u2] = sunDirection(at("2026-03-20T06:00:00Z"), 0, 0);
  assert.ok(e2 > 0.999 && Math.abs(n2) < 0.01 && Math.abs(u2) < 0.03);
});

test("timeOfDayLights: day and night are the table's ends, the sun's direction its azimuth and zenith angle", () => {
  const noon = timeOfDayLights(at("2026-06-21T03:00:00Z"), 139.77, 35.68);
  assert.deepEqual(noon, [
    { id: "ambient", type: "ambient", properties: { color: "#ffffff", intensity: 0.5 } },
    {
      id: "sun",
      type: "directional",
      properties: { color: "#fff4e6", intensity: 0.5, direction: [198.21584231216275, 90 - 77.19959278765559] },
    },
  ]);
  const night = timeOfDayLights(at("2026-06-21T15:00:00Z"), 139.77, 35.68);
  assert.deepEqual(night[0].properties, { color: "#4a5a8c", intensity: 0.3 });
  assert.equal(night[1].properties.intensity, 0);
  assert.equal(night[1].properties.color, "#ff8c59");
  assert.equal(night[1].properties.direction![1], 90);
});

test("timeOfDayLights eases through twilight without jumps", () => {
  assert.deepEqual(SUN_LIGHT_STOPS.map((s) => s[0]), [-6, 0, 6]);
  // Every minute of a Tokyo evening: the sun's intensity follows its altitude and never jumps.
  let last: { altitude: number; intensity: number } | null = null;
  let twilight = 0;
  for (let m = 0; m < 180; m++) {
    const date = new Date(Date.parse("2026-06-21T08:30:00Z") + m * 60000);
    const { altitude } = sunPosition(date, 139.77, 35.68);
    const [ambient, sun] = timeOfDayLights(date, 139.77, 35.68);
    const intensity = sun.properties.intensity;
    assert.match(ambient.properties.color, /^#[0-9a-f]{6}$/);
    assert.ok(intensity >= 0 && intensity <= 0.5 && ambient.properties.intensity >= 0.3);
    if (altitude > -6 && altitude < 6) twilight++;
    if (last) {
      assert.ok(altitude < last.altitude);
      assert.ok(intensity <= last.intensity);
      assert.ok(last.intensity - intensity < 0.02);
    }
    last = { altitude, intensity };
  }
  assert.ok(twilight > 30);
  assert.equal(last!.intensity, 0);
});
