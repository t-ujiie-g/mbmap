// The mbmap side of bench/cesium/run.mjs: PLATEAU's buildings by mbmap/3d's tilesLayer over a plain
// background, at the camera of ?view=; `__run` adds the layer and waits until it settles, `__orbit`
// turns the camera a degree a frame.
import { Map } from "mbmap";
import { tilesLayer } from "mbmap/3d";
import { HEIGHT_OFFSET, ORBIT_FRAMES, VIEWS, quantiles, settle, trackFrames } from "./views.mjs";

const frames = trackFrames();
const view = VIEWS[Number(new URLSearchParams(location.search).get("view") ?? 0)];
const map = new Map({
  container: "map",
  center: view.center,
  zoom: view.zoom,
  pitch: view.pitch,
  bearing: view.bearing,
  attributionControl: false,
  style: { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": "#ffffff" } }] },
});
map.on("error", (e) => console.error(e.error));
const loaded = map.once("load");
const url = new URL("/bench/fixtures/plateau-chiyoda/tileset.json", location.href).href;
let layer = null;

/** The drawn tiles' content URLs, or null while anything is asked for or loading. */
function drawn() {
  map.triggerRepaint();
  if (!layer.idle || layer.selected.length === 0 || map.isMoving()) return null;
  return layer.selected.map((t) => t.contentUrl ?? t.path).sort().join();
}

window.__run = async () => {
  await loaded;
  const t0 = performance.now();
  layer = tilesLayer({ id: "plateau", url, height: HEIGHT_OFFSET });
  map.addLayer(layer);
  await layer.ready;
  const settled = await settle(drawn);
  const tiles = layer.selected;
  return {
    settleMs: settled - t0,
    selected: tiles.length,
    selectedWithContent: tiles.filter((t) => t.contentUrl).length,
    contents: tiles.filter((t) => t.contentUrl).map((t) => new URL(t.contentUrl).pathname).sort(),
  };
};

// Clips as bench/cesium/clip.mjs asks (Map.setClipping's options, or null) over a black background, then settles.
window.__clip = async (c) => {
  map.setPaintProperty("background", "background-color", "#000000");
  map.setClipping(c);
  await settle(drawn);
};

window.__orbit = async () => {
  frames.clear();
  await new Promise((done) => {
    let i = 0;
    const step = () => {
      map.jumpTo({ bearing: view.bearing + ++i });
      if (i < ORBIT_FRAMES) requestAnimationFrame(step);
      else done();
    };
    requestAnimationFrame(step);
  });
  const cpu = quantiles([...frames.values()]);
  map.jumpTo({ bearing: view.bearing });
  await settle(drawn);
  return cpu;
};

window.__renderer = () => {
  const gl = document.createElement("canvas").getContext("webgl2");
  const ext = gl?.getExtension("WEBGL_debug_renderer_info");
  return ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl?.getParameter(gl.RENDERER) ?? null;
};
window.__pageReady = true;
