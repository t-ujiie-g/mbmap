// The showcase's behaviour for the plain-DOM examples, once the map has loaded; each example only
// says how it starts the map and how a new style reaches it (`applyStyle`).
import { describe } from "./analysis.js";
import { mountAnalysis, routeAnalysisClicks } from "./analyze.js";
import { mountControls } from "./controls.js";
import { mountCoordinates } from "./coordinates.js";
import { mountData } from "./data.js";
import { mountServices } from "./services.js";
import { mountDraw } from "./draw.js";
import { identifyWhenIdle, mountMeasurement } from "./measure.js";
import { pinDestinations, saveImage } from "./overlay.js";
import { mountPanel, panelControllers } from "./panel.js";
import { hoverPlaces, mountIdentify } from "./pick.js";
import { DESTINATIONS, PLACES } from "./places.js";
import { mountProfile } from "./profile.js";
import { cameraRows, nearLines, showRows } from "./readout.js";
import { keepRadiusRing } from "./ring.js";
import { mountSearch } from "./search.js";
import { zoomIntoClusters } from "./stations.js";
import { createStyle, modeCamera, modeEase, withMarker } from "./style.js";
import { mountTable } from "./table.js";

/** Wires the panel to `map`; returns `showCamera` and `update` for the example's own move events. */
export function mountApp(map, status, applyStyle) {
  let mode = "2d";
  let places = PLACES;
  let plane = null;
  let pending = 0;

  // The features under a click (from the workers that hold the geometry) unless it measures or draws.
  let draw = null;
  const measurement = mountMeasurement(map, () => draw?.setMode(null));
  draw = mountDraw(map, measurement);
  const analysis = mountAnalysis(map, () => {
    draw.setMode(null);
    measurement.clear();
  });
  routeAnalysisClicks(map, analysis, [measurement, draw]);
  identifyWhenIdle(map, mountIdentify(map), () => measurement.state.mode || draw.state.mode || analysis.state.picking);
  mountProfile(map, measurement);
  mountCoordinates(map, status);
  hoverPlaces(map);
  keepRadiusRing(map);
  zoomIntoClusters(map);
  pinDestinations(map, document.body);
  mountControls(map, document.body, status);
  const panel = panelControllers(map, () => mode, () => places);
  mountPanel(panel);
  mountSearch(map, () => places);
  mountTable(map);
  mountData(map);
  mountServices(map);

  const showButtons = () => {
    for (const b of document.querySelectorAll("#modes button")) b.setAttribute("aria-pressed", String(b.dataset.mode === mode));
  };
  const showCamera = () => {
    const camera = { center: map.getCenter(), zoom: map.getZoom(), bearing: map.getBearing(), pitch: map.getPitch() };
    showRows(document.getElementById("camera"), cameraRows(camera, plane));
  };
  const update = async () => {
    const ticket = ++pending;
    const result = await describe(map.getCenter());
    if (ticket !== pending) return;
    plane = result.plane;
    showCamera();
    document.getElementById("near").replaceChildren(...nearLines(result.near).map((n) => Object.assign(document.createElement("li"), { textContent: n })));
    window.__described = result;
  };

  // The style changes in place: tiles of what stays alike are kept.
  document.getElementById("modes").addEventListener("click", (e) => {
    const next = e.target.dataset?.mode;
    if (!next || next === mode) return;
    mode = next;
    applyStyle(createStyle(mode, panel.hidden(), places, panel.basemaps.state.active ?? "map"));
    map.easeTo(modeEase(mode, map.getZoom()));
    showButtons();
  });
  document.getElementById("destinations").replaceChildren(
    ...DESTINATIONS.map((d) => {
      const b = Object.assign(document.createElement("button"), { textContent: d.name });
      b.addEventListener("click", () => map.flyTo({ center: d.center, zoom: d.zoom, ...modeCamera(mode) }));
      return b;
    }),
  );
  // From the source's data, which the table's field editor may have changed.
  document.getElementById("marker").addEventListener("click", async () => {
    places = await map.getSource("places").getData();
    places = withMarker(places, map.getCenter(), `印 ${places.features.length - PLACES.features.length + 1}`);
    map.getSource("places").setData(places);
  });
  document.getElementById("save").addEventListener("click", () => saveImage(map));
  showButtons();
  showCamera();
  update();
  return { showCamera, update };
}
