// What the showcase computes off the map, in mbmap/analysis's worker: the
// places within 5 km of the view's center (a geodesic buffer, then a
// point-in-polygon test) and the center in Japan's plane rectangular system.
import { load, transform } from "mbmap/analysis";
import { PLACES } from "./places.js";

export const RADIUS_METERS = 5000;

// Origins of the plane rectangular zones I-XIX (lng, lat) and their EPSG codes on JGD2011.
const ORIGINS = [
  [129.5, 33], [131, 33], [132 + 1 / 6, 36], [133.5, 33], [134 + 1 / 3, 36], [136, 36], [137 + 1 / 6, 36],
  [138.5, 36], [139 + 5 / 6, 36], [140 + 5 / 6, 40], [140.25, 44], [142.25, 44], [144.25, 44], [142, 26],
  [127.5, 26], [124, 26], [131, 26], [136, 20], [154, 26],
];
const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX"];

/** The zone whose origin is nearest (the official zones follow prefecture lines). */
function nearestZone(lng, lat) {
  let best = 0;
  ORIGINS.forEach(([x, y], i) => {
    const [bx, by] = ORIGINS[best];
    if ((x - lng) ** 2 + (y - lat) ** 2 < (bx - lng) ** 2 + (by - lat) ** 2) best = i;
  });
  return { epsg: 6669 + best, name: `第${ROMAN[best]}系` };
}

let places = null;

/** The places near `center` and `center` in the nearest plane rectangular zone. */
export async function describe(center) {
  places ??= load(PLACES);
  const all = await places;
  const point = await load({ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [center.lng, center.lat] } });
  const zone = await point.buffer(RADIUS_METERS);
  const inside = await all.pointsWithin(zone);
  point.dispose();
  zone.dispose();
  const z = nearestZone(center.lng, center.lat);
  const [x, y] = await transform([center.lng, center.lat], 4326, z.epsg);
  return {
    near: Array.from(inside, (i) => PLACES.features[i].properties.name),
    plane: { zone: z.name, epsg: z.epsg, x, y },
  };
}
