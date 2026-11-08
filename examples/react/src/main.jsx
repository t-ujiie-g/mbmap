// The showcase in React 19 with <mb-map>: attributes and properties as
// props, the element's CustomEvents as `on<event>` props. The map keeps its
// own state; React renders the panel from the events.
import { StrictMode, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import "mbmap/element";
import { describe } from "../../shared/analysis.js";
import { pinDestinations, saveImage } from "../../shared/overlay.js";
import { panelControllers } from "../../shared/panel.js";
import { hoverPlaces } from "../../shared/pick.js";
import { DESTINATIONS, PLACES } from "../../shared/places.js";
import { cameraRows, nearLines } from "../../shared/readout.js";
import { keepRadiusRing } from "../../shared/ring.js";
import { TABS, VARIANTS } from "../../shared/shell.js";
import { zoomIntoClusters } from "../../shared/stations.js";
import { createStyle, modeCamera, withMarker } from "../../shared/style.js";
import { MapControls } from "./controls.jsx";
import { DataPanel } from "./data.jsx";
import { ServicesPanel } from "./services.jsx";
import { Icon } from "./icon.jsx";
import { useIdentify } from "./identify.jsx";
import { Basemaps, LayerChecklist, Legend } from "./panel.jsx";
import { SearchBar } from "./search.jsx";
import { AttributeTable } from "./table.jsx";

function Tab({ id, tab, children }) {
  return <section role="tabpanel" data-panel={id} hidden={id !== tab}>{children}</section>;
}

function App() {
  const ref = useRef(null);
  const [mode, setMode] = useState("2d");
  const [tab, setTab] = useState("explore");
  const [collapsed, setCollapsed] = useState(false);
  const [camera, setCamera] = useState({ center: { lng: 139.7671, lat: 35.6812 }, zoom: 15, bearing: 0, pitch: 0 });
  const [described, setDescribed] = useState(null);
  const [panel, setPanel] = useState(null);
  const [status, setStatus] = useState(null);
  const modeRef = useRef(mode);
  const [map, setMap] = useState(null);
  const tools = useIdentify(map, status);
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
  // From the source's data, which the table's field editor may have changed.
  const addMarker = async () => {
    const map = ref.current.map;
    if (!map) return;
    const data = await map.getSource("places").getData();
    places.current = withMarker(data, ref.current.center, `印 ${data.features.length - PLACES.features.length + 1}`);
    map.getSource("places").setData(places.current);
  };

  const onLoad = (e) => {
    window.__loaded = performance.now();
    const map = e.detail.map;
    window.__map = map;
    hoverPlaces(map);
    keepRadiusRing(map);
    zoomIntoClusters(map);
    pinDestinations(map, document.body);
    setMap(map);
    setPanel(panelControllers(map, () => modeRef.current, () => places.current));
    update(e.detail.center);
  };
  const go = (d) => ref.current.map?.flyTo({ center: d.center, zoom: d.zoom, ...modeCamera(mode) });
  const rows = cameraRows(camera, described?.plane);

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
      {map && <MapControls map={map} status={status} />}
      {tools?.coordinates}
      <aside className="panel">
        <div className={collapsed ? "panel-card collapsed" : "panel-card"}>
          <header className="brand">
            <a className="logo" href="../">mbmap</a>
            <nav className="variants" aria-label="書き方">
              {VARIANTS.map(([path, label]) => <a key={path} href={`../${path}/`} aria-current={path === "react" ? "page" : undefined}>{label}</a>)}
            </nav>
            <button className="collapse" title="パネルを畳む" aria-label="パネルを畳む" onClick={() => setCollapsed(!collapsed)}><Icon name="chevron" /></button>
          </header>
          {map ? <SearchBar map={map} places={() => places.current} /> : <div id="search" />}
          <div className="tabs" role="tablist">
            {TABS.map(([id, label]) => <button key={id} role="tab" data-tab={id} aria-selected={id === tab} onClick={() => setTab(id)}>{label}</button>)}
          </div>
          <div className="tab-body">
            <Tab id="explore" tab={tab}>
              <h2>移動</h2>
              <div id="destinations" className="chips">
                {DESTINATIONS.map((d) => <button key={d.name} onClick={() => go(d)}>{d.name}</button>)}
              </div>
              <h2>クリックした地物</h2>
              {tools?.picked}
              <h2>中心から 5 km 以内の地点</h2>
              <ul id="near" className="plain-list">{nearLines(described?.near ?? []).map((n) => <li key={n}>{n}</li>)}</ul>
              <h2>カメラ</h2>
              <dl id="camera" className="rows">{rows.map(([k, v], i) => [<dt key={`k${i}`}>{k}</dt>, <dd key={`v${i}`}>{v}</dd>])}</dl>
            </Tab>
            <Tab id="layers" tab={tab}>
              <h2>背景地図</h2>
              {panel && <Basemaps c={panel.basemaps} />}
              <h2>レイヤー</h2>
              {panel && <LayerChecklist c={panel.layers} />}
              {panel && <Legend c={panel.legend} />}
            </Tab>
            <Tab id="draw" tab={tab}>
              <h2>形</h2>
              {tools?.draw}
            </Tab>
            <Tab id="measure" tab={tab}>
              <h2>距離と面積</h2>
              {tools?.measure}
              <h2>断面図</h2>
              {tools?.profile}
            </Tab>
            <Tab id="analysis" tab={tab}>
              {tools?.analysis}
            </Tab>
            <Tab id="data" tab={tab}>
              <h2>読み込み</h2>
              {map && <DataPanel map={map} />}
              <h2>Web サービス</h2>
              {map && <ServicesPanel map={map} />}
              <h2>地点の一覧</h2>
              {map && <AttributeTable map={map} />}
              <div className="chips"><button id="marker" onClick={addMarker}>中心に印を置く</button></div>
            </Tab>
          </div>
        </div>
      </aside>
      <div className="map-actions">
        <div id="modes" className="segmented">
          {["2d", "3d"].map((m) => <button key={m} data-mode={m} aria-pressed={mode === m} onClick={() => switchMode(m)}>{m.toUpperCase()}</button>)}
        </div>
        <button id="save" title="画像を保存" aria-label="画像を保存" onClick={() => ref.current.map && saveImage(ref.current.map)}><Icon name="camera" /></button>
      </div>
      <div className="statusbar" ref={setStatus} />
    </>
  );
}

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
