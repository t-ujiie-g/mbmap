// One map drawn on by mbmap/draw (?engine=mbmap) or by terra-draw 1.37 on MapLibre
// (?engine=terradraw): `__mode(m)` picks a mode, `__features()` gives the GeoJSON drawn.
const engine = new URLSearchParams(location.search).get("engine");
const CENTER = [139.7671, 35.6812];
const style = { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": "#f5f3ee" } }] };

if (engine === "terradraw") {
  const maplibregl = await import("/bench/node_modules/maplibre-gl/dist/maplibre-gl.mjs");
  const td = await import("terra-draw");
  const { TerraDrawMapLibreGLAdapter } = await import("/bench/node_modules/terra-draw-maplibre-gl-adapter/dist/terra-draw-maplibre-gl-adapter.module.js");
  const map = new maplibregl.Map({ container: "map", style, center: CENTER, zoom: 15, attributionControl: false, fadeDuration: 0 });
  await new Promise((r) => map.once("load", r));
  const draw = new td.TerraDraw({
    adapter: new TerraDrawMapLibreGLAdapter({ map }),
    modes: [
      new td.TerraDrawPointMode(), new td.TerraDrawLineStringMode(), new td.TerraDrawPolygonMode({ snapping: { toCoordinate: true } }),
      new td.TerraDrawSelectMode({
        flags: { polygon: { feature: { draggable: true, coordinates: { midpoints: true, draggable: true, deletable: true } } } },
      }),
      new td.TerraDrawRectangleMode(), new td.TerraDrawCircleMode({ projection: "globe" }), new td.TerraDrawFreehandMode(),
    ],
  });
  draw.start();
  window.__mode = (m) => draw.setMode(m);
  window.__features = () => draw.getSnapshot().filter((f) => !f.properties.closingPoint && !f.properties.coordinatePoint && !f.properties.selectionPoint && !f.properties.midPoint && !f.properties.snappingPoint);
  window.__clear = () => draw.clear();
} else {
  const { Map } = await import("/npm/dist/index.js");
  const { createDraw } = await import("/npm/dist/draw.js");
  const geodesic = await import("/npm/dist/geodesic.js");
  const map = new Map({ container: "map", style, center: CENTER, zoom: 15, attributionControl: false });
  await map.once("load");
  const draw = createDraw(map, { geodesic, snapping: { vertices: true, lines: false } });
  window.__mode = (m) => draw.setMode(m);
  window.__features = () => draw.state.features;
  window.__clear = () => draw.clear();
}
window.__ready = true;
