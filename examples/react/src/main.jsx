// The showcase in React 19 with <mb-map>: attributes and properties as
// props, the element's CustomEvents as `on<event>` props. The map keeps its
// own state; React renders the panel from the events.
import { StrictMode, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import "mbmap/element";
import { describe, RADIUS_METERS } from "../../shared/analysis.js";
import { pinDestinations, saveImage } from "../../shared/overlay.js";
import { panelControllers } from "../../shared/panel.js";
import { MapControls } from "./controls.jsx";
import { Basemaps, LayerChecklist, Legend } from "./panel.jsx";
import { describeFeature, hoverPlaces } from "../../shared/pick.js";
import { DESTINATIONS } from "../../shared/places.js";
import { PLACES } from "../../shared/places.js";
import { createStyle, modeCamera, withMarker } from "../../shared/style.js";

const fixed = (v, n) => v.toFixed(n);

function App() {
  const ref = useRef(null);
  const [mode, setMode] = useState("2d");
  const [camera, setCamera] = useState({ center: { lng: 139.7671, lat: 35.6812 }, zoom: 15, bearing: 0, pitch: 0 });
  const [described, setDescribed] = useState(null);
  const [panel, setPanel] = useState(null);
  const modeRef = useRef(mode);
  const [picked, setPicked] = useState(null);
  const [map, setMap] = useState(null);
  const places = useRef(PLACES);
  const pending = useRef(0);
  // A new style object goes to the map's setStyle: tiles of what stays alike are kept.
  // Layer visibility, basemaps and markers change through the map itself, so the style reads them only on a mode switch.
  const style = useMemo(() => createStyle(mode, panel?.hidden(), places.current, panel?.basemaps.state.active ?? "map"), [mode]);

  const update = useCallback(async (center) => {
    const ticket = ++pending.current;
    const result = await describe(center);
    if (ticket !== pending.current) return;
    setDescribed(result);
    window.__described = result;
  }, []);

  useEffect(() => {
    ref.current.mapStyle = style;
  }, [style]);

  const switchMode = (m) => {
    if (m === mode) return;
    modeRef.current = m;
    setMode(m);
    ref.current.map?.easeTo({ ...modeCamera(m), duration: 1000 });
  };
  const addMarker = () => {
    places.current = withMarker(places.current, ref.current.center, `印 ${places.current.features.length - PLACES.features.length + 1}`);
    ref.current.map?.getSource("places").setData(places.current);
  };

  const onLoad = (e) => {
    window.__loaded = performance.now();
    const map = e.detail.map;
    window.__map = map;
    // The topmost feature under a click, from the workers that hold the geometry.
    map.on("click", (ev) => map.queryRenderedFeatures(ev.point).then((features) => {
      const rows = describeFeature(features) ?? [["—", "何もありません"]];
      setPicked(rows);
      window.__picked = rows;
    }));
    hoverPlaces(map);
    pinDestinations(map, document.body);
    setMap(map);
    setPanel(panelControllers(map, () => modeRef.current, () => places.current));
    update(e.detail.center);
  };
  const go = (d) => ref.current.map?.flyTo({ center: d.center, zoom: d.zoom, ...modeCamera(mode) });
  const rows = [
    ["経度", fixed(camera.center.lng, 5)],
    ["緯度", fixed(camera.center.lat, 5)],
    ["ズーム", fixed(camera.zoom, 2)],
    ["方位", `${fixed(camera.bearing, 1)}°`],
    ["傾き", `${fixed(camera.pitch, 1)}°`],
  ];
  const plane = described?.plane;
  if (plane) rows.push([`平面直角 ${plane.zone}`, `X ${fixed(plane.y, 1)} m`], ["", `Y ${fixed(plane.x, 1)} m`]);
  const near = described?.near ?? [];

  return (
    <>
      <mb-map
        ref={ref}
        center="139.7671,35.6812"
        zoom="15"
        attribution-control="false"
        onmb-load={onLoad}
        onmb-move={(e) => setCamera(e.detail)}
        onmb-moveend={(e) => update(e.detail.center)}
      />
      {map && <MapControls map={map} />}
      <aside className="panel">
        <h1>mbmap</h1>
        <p className="variant">React（<code>&lt;mb-map&gt;</code> を JSX で）</p>
        <h2>表示</h2>
        <div id="modes">
          {["2d", "3d"].map((m) => (
            <button key={m} aria-pressed={mode === m} onClick={() => switchMode(m)}>{m.toUpperCase()}</button>
          ))}
        </div>
        <h2>背景地図</h2>
        {panel && <Basemaps c={panel.basemaps} />}
        <h2>レイヤー</h2>
        {panel && <LayerChecklist c={panel.layers} />}
        <button id="marker" onClick={addMarker}>中心に印を置く</button>
        <button id="save" onClick={() => ref.current.map && saveImage(ref.current.map)}>画像を保存</button>
        {panel && <Legend c={panel.legend} />}
        <h2>クリックした地物</h2>
        <dl id="picked">
          {(picked ?? [["—", "地図をクリック"]]).map(([k, v], i) => [<dt key={`k${i}`}>{k}</dt>, <dd key={`v${i}`}>{v}</dd>])}
        </dl>
        <h2>移動</h2>
        <div id="destinations">
          {DESTINATIONS.map((d) => <button key={d.name} onClick={() => go(d)}>{d.name}</button>)}
        </div>
        <h2>カメラ</h2>
        <dl id="camera">
          {rows.map(([k, v], i) => [<dt key={`k${i}`}>{k}</dt>, <dd key={`v${i}`}>{v}</dd>])}
        </dl>
        <h2>中心から 5 km 以内の地点</h2>
        <ul id="near">
          {(near.length ? near : [`なし（半径 ${RADIUS_METERS / 1000} km）`]).map((n) => <li key={n}>{n}</li>)}
        </ul>
        <nav><a href="../html/">HTML</a><a href="../element/">Web Component</a><a href="../react/">React</a></nav>
      </aside>
    </>
  );
}

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
