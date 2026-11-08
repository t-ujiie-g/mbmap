// The sun's position, ported from suncalc 2.1.1 (BSD-2-Clause, Copyright (c) 2026 Volodymyr
// Agafonkin; NOTICE), computed as it does so results are bit-identical (`npm run sun:golden`).

const { PI, sin, cos, tan, asin, atan2 } = Math;
const rad = PI / 180;
const dayMs = 1000 * 60 * 60 * 24;
const J1970 = 2440588;
const J2000 = 2451545;

/** Where the sun stands: `azimuth` in degrees clockwise from north, `altitude` the apparent
 * (refraction-corrected) height above the horizon in degrees. */
export interface SunPosition {
  azimuth: number;
  altitude: number;
}

/** An entry of a style's `lights`. */
export interface Light {
  id: string;
  type: "ambient" | "directional";
  properties: { color: string; intensity: number; direction?: [number, number] };
}

// ΔT = TT − UT in seconds (Espenak & Meeus' polynomials), from days since J2000.
function deltaT(d: number): number {
  const y = 2000 + d / 365.2425;
  let t;
  if (y < 1920) { t = y - 1900; return -2.79 + t * (1.494119 + t * (-0.0598939 + t * (0.0061966 - t * 0.000197))); }
  if (y < 1941) { t = y - 1920; return 21.20 + t * (0.84493 + t * (-0.076100 + t * 0.0020936)); }
  if (y < 1961) { t = y - 1950; return 29.07 + t * (0.407 + t * (-1 / 233 + t / 2547)); }
  if (y < 1986) { t = y - 1975; return 45.45 + t * (1.067 + t * (-1 / 260 - t / 718)); }
  if (y < 2005) { t = y - 2000; return 63.86 + t * (0.3345 + t * (-0.060374 + t * (0.0017275 + t * (0.000651814 + t * 0.00002373599)))); }
  if (y < 2050) { t = y - 2000; return 62.92 + t * (0.32217 + t * 0.005589); }
  t = (y - 1820) / 100; return -20 + 32 * t * t - 0.5628 * (2150 - y);
}

/**
 * The sun's position at `date` seen from `lng`, `lat` (degrees): suncalc's `getPosition(date, lat,
 * lng)`, whose arguments come in the other order. An invalid date gives NaN.
 */
export function sunPosition(date: Date | number, lng: number, lat: number): SunPosition {
  const lw = rad * -lng;
  const phi = rad * lat;
  const d = date.valueOf() / dayMs - 0.5 + J1970 - J2000;
  // Meeus ch. 25 on Terrestrial Time; sidereal time stays on UT.
  const t = (d + deltaT(d) / 86400) / 36525;
  const L0 = rad * (280.46646 + t * (36000.76983 + t * 0.0003032));
  const M = rad * (357.52911 + t * (35999.05029 - t * 0.0001537));
  const sinM = sin(M);
  const cosM = cos(M);
  const C = rad * ((1.914602 - t * (0.004817 + t * 0.000014)) * sinM +
    (0.019993 - 0.000101 * t) * 2 * sinM * cosM + 0.000289 * sinM * (3 - 4 * sinM * sinM));
  const Om = rad * (125.04 - 1934.136 * t);
  const L = L0 + C - rad * (0.00569 + 0.00478 * sin(Om));
  const e = rad * (23.439291 - t * (0.0130042 + t * (0.00000016 - t * 0.000000504))) + rad * 0.00256 * cos(Om);
  const ra = atan2(cos(e) * sin(L), cos(L));
  const dec = asin(sin(e) * sin(L));
  const H = rad * (280.46061837 + 360.98564736629 * d) - lw - ra;
  const h = asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(H));
  // Meeus 16.4, valid for positive altitudes only.
  const r = h < 0 ? 0 : h;
  return {
    azimuth: (atan2(sin(H), cos(H) * sin(phi) - tan(dec) * cos(phi)) / rad + 540) % 360,
    altitude: (h + 0.0002967 / tan(r + 0.00312536 / (r + 0.08901179))) / rad,
  };
}

/**
 * A unit vector [east, north, up] toward the sun at `date` from `lng`, `lat`: with azimuth A and
 * apparent altitude h of `sunPosition`, [cos h sin A, cos h cos A, sin h].
 */
export function sunDirection(date: Date | number, lng: number, lat: number): [number, number, number] {
  const { azimuth, altitude } = sunPosition(date, lng, lat);
  const a = azimuth * rad;
  const h = altitude * rad;
  return [cos(h) * sin(a), cos(h) * cos(a), sin(h)];
}

/** `timeOfDayLights`' stops by the sun's altitude in degrees, 6° apart: [altitude, ambient color,
 * ambient intensity, sun color, sun intensity]; night up to -6°, twilight to 6°, day above. */
export const SUN_LIGHT_STOPS: readonly (readonly [number, number, number, number, number])[] = [
  [-6, 0x4a5a8c, 0.3, 0xff8c59, 0],
  [0, 0x9c8ca6, 0.4, 0xff9c59, 0.25],
  [6, 0xffffff, 0.5, 0xfff4e6, 0.5],
];

/**
 * The style `lights` for `date` at `lng`, `lat`: an ambient light and the sun as a directional light,
 * colors and intensities eased between `SUN_LIGHT_STOPS` (smoothstep within each span). `direction`
 * is [azimuthal, polar]: the sun's azimuth clockwise from north and its angle from straight up, held
 * at 90° while it is below the horizon. Throws a RangeError for an invalid date.
 */
export function timeOfDayLights(date: Date | number, lng: number, lat: number): Light[] {
  const { azimuth, altitude } = sunPosition(date, lng, lat);
  if (altitude !== altitude) throw new RangeError("invalid date");
  const [a, b] = altitude > 0 ? SUN_LIGHT_STOPS.slice(1) : SUN_LIGHT_STOPS;
  const u = Math.min(1, Math.max(0, (altitude - a[0]) / 6));
  const t = u * u * (3 - 2 * u);
  const mix = (x: number, y: number) => x * (1 - t) + y * t;
  const color = (k: number) =>
    "#" + [16, 8, 0].map((s) => (256 + Math.round(mix((a[k] >> s) & 255, (b[k] >> s) & 255))).toString(16).slice(1)).join("");
  return [
    { id: "ambient", type: "ambient", properties: { color: color(1), intensity: mix(a[2], b[2]) } },
    {
      id: "sun",
      type: "directional",
      properties: { color: color(3), intensity: mix(a[4], b[4]), direction: [azimuth, Math.min(90, 90 - altitude)] },
    },
  ];
}
