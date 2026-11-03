// mbmap/draw over `?shapes=` polygons of 32 vertices: per pointer move while a polygon is drawn,
// the time until the map is idle again (the shape under way on screen).
const params = new URLSearchParams(location.search);
const n = Number(params.get("shapes") ?? 500);
const CENTER = [139.7671, 35.6812];
const { Map } = await import("/npm/dist/index.js");
const { createDraw } = await import("/npm/dist/draw.js");
const style = { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": "#f5f3ee" } }] };
const map = new Map({ container: "map", style, center: CENTER, zoom: 13, attributionControl: false });
await map.once("load");
const draw = createDraw(map, { snapping: true });
let seed = 3;
const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
const shapes = [];
for (let i = 0; i < n; i++) {
  const [x, y] = [CENTER[0] + (rand() - 0.5) * 0.1, CENTER[1] + (rand() - 0.5) * 0.06];
  const ring = [];
  for (let k = 0; k < 32; k++) ring.push([x + 0.002 * Math.cos((2 * Math.PI * k) / 32), y + 0.0015 * Math.sin((2 * Math.PI * k) / 32)]);
  ring.push(ring[0]);
  shapes.push({ geometry: { type: "Polygon", coordinates: [ring] } });
}
draw.setMode("polygon");
draw.add(shapes);
await map.once("idle");
window.__map = map;
window.__ready = true;
