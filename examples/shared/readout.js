// What the panel reads out of the camera, shared by the three examples.
import { RADIUS_METERS } from "./analysis.js";

const fixed = (v, n) => v.toFixed(n);

/** The rows of `#camera` for a `{ center, zoom, bearing, pitch }` and the center's plane rectangular coordinates. */
export function cameraRows({ center, zoom, bearing, pitch }, plane) {
  const rows = [
    ["経度", fixed(center.lng, 5)],
    ["緯度", fixed(center.lat, 5)],
    ["ズーム", fixed(zoom, 2)],
    ["方位", `${fixed(bearing, 1)}°`],
    ["傾き", `${fixed(pitch, 1)}°`],
  ];
  if (plane) rows.push([`平面直角 ${plane.zone}`, `X ${fixed(plane.y, 1)} m`], ["", `Y ${fixed(plane.x, 1)} m`]);
  return rows;
}

/** The lines of `#near`: the places, or that there are none. */
export const nearLines = (near) => (near.length ? near : [`なし（半径 ${RADIUS_METERS / 1000} km）`]);

/** Fills `dl` with `[label, value]` rows. */
export function showRows(dl, rows) {
  dl.replaceChildren(...rows.flatMap(([k, v]) => [Object.assign(document.createElement("dt"), { textContent: k }), Object.assign(document.createElement("dd"), { textContent: v })]));
}
