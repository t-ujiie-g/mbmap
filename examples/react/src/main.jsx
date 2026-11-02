// The showcase in React 19 with <mb-map>: attributes and properties as
// props, the element's CustomEvents as `on<event>` props. The map keeps its
// own state; React renders the panel from the events.
import { StrictMode, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import "mbmap/element";
import { describe, RADIUS_METERS } from "../../shared/analysis.js";
import { DESTINATIONS } from "../../shared/places.js";
import { createStyle, modeCamera } from "../../shared/style.js";

const fixed = (v, n) => v.toFixed(n);

function App() {
  const ref = useRef(null);
  const [mode, setMode] = useState("2d");
  const [camera, setCamera] = useState({ center: { lng: 139.7671, lat: 35.6812 }, zoom: 15, bearing: 0, pitch: 0 });
  const [described, setDescribed] = useState(null);
  const pending = useRef(0);
  // A new style object starts the map again at its camera (setStyle comes in Phase 12.2).
  const style = useMemo(() => createStyle(mode), [mode]);

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

  const onLoad = (e) => {
    window.__loaded = performance.now();
    window.__map = e.detail.map;
    // After a switch, tilt into the new mode.
    if (e.detail.pitch !== modeCamera(mode).pitch) e.detail.map.easeTo({ ...modeCamera(mode), duration: 1000 });
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
        onmb-load={onLoad}
        onmb-move={(e) => setCamera(e.detail)}
        onmb-moveend={(e) => update(e.detail.center)}
      />
      <aside className="panel">
        <h1>mbmap</h1>
        <p className="variant">React（<code>&lt;mb-map&gt;</code> を JSX で）</p>
        <h2>表示</h2>
        <div id="modes">
          {["2d", "3d"].map((m) => (
            <button key={m} aria-pressed={mode === m} onClick={() => setMode(m)}>{m.toUpperCase()}</button>
          ))}
        </div>
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
