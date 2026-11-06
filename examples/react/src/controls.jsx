// The map's controls in React, from the same `mbmap/ui` controllers and markup as the plain-DOM examples.
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { createAttribution, createFullscreen, createGeolocation, createNavigation, createScale } from "mbmap/ui";
import { LOCATION_LABELS } from "../../shared/controls.js";
import { Icon } from "./icon.jsx";
import { useController } from "./use-controller.js";

function Location({ map, geo }) {
  const g = useController(geo);
  const [at, setAt] = useState(null);
  useEffect(() => {
    if (!g.position) return setAt(null);
    const t = map.track(g.position.lngLat, setAt);
    return () => t.remove();
  }, [map, g.position]);
  if (!at) return null;
  return <div className="location" style={{ transform: `translate(${at.x}px, ${at.y}px)`, "--accuracy": `${g.accuracyRadius}px` }} />;
}

function Buttons({ c }) {
  const nav = useController(c.nav);
  const geo = useController(c.geo);
  const full = useController(c.full);
  return (
    <div className="controls">
      <div className="control-group">
        <button aria-label="拡大" title="拡大" disabled={!nav.canZoomIn} onClick={() => c.nav.zoomIn()}><Icon name="plus" /></button>
        <button aria-label="縮小" title="縮小" disabled={!nav.canZoomOut} onClick={() => c.nav.zoomOut()}><Icon name="minus" /></button>
        <button aria-label="北を上に" title="北を上に" onClick={() => c.nav.resetNorth(true)}>
          <span className="needle" style={{ transform: `rotateX(${nav.pitch}deg) rotateZ(${-nav.bearing}deg)` }}><Icon name="north" /></span>
        </button>
      </div>
      <div className="control-group">
        <button aria-label="最初の位置へ" title="最初の位置へ" onClick={() => c.nav.home()}><Icon name="home" /></button>
        <button aria-label={LOCATION_LABELS[geo.status]} title={LOCATION_LABELS[geo.status]} aria-pressed={geo.status !== "off" && geo.status !== "unavailable"} data-status={geo.status} disabled={geo.status === "unavailable"} onClick={() => c.geo.trigger()}><Icon name="locate" /></button>
        <button aria-label="全画面" title="全画面" aria-pressed={full.active} onClick={() => c.full.toggle()}><Icon name="fullscreen" /></button>
      </div>
    </div>
  );
}

function Status({ c }) {
  const scale = useController(c.scale);
  const credits = useController(c.attribution);
  return (
    <>
      <div className="scale" style={{ width: scale.width }}>{scale.label}</div>
      <div className="credits">{credits.text}</div>
    </>
  );
}

/** The controls over `map`, the scale and credits in the status bar `status`; their controllers are made once and destroyed with it. */
export function MapControls({ map, status }) {
  const [c] = useState(() => ({
    nav: createNavigation(map),
    geo: createGeolocation(map, { trackUserLocation: true }),
    full: createFullscreen(map, { container: document.documentElement }),
    scale: createScale(map, { maxWidth: 120 }),
    attribution: createAttribution(map),
  }));
  useEffect(() => {
    window.__controls = c;
    return () => Object.values(c).forEach((x) => x.destroy());
  }, [c]);
  const full = useController(c.full);
  useEffect(() => {
    document.documentElement.classList.toggle("pseudo-fullscreen", full.pseudo && full.active);
  }, [full]);
  return (
    <>
      <Location map={map} geo={c.geo} />
      <Buttons c={c} />
      {status && createPortal(<Status c={c} />, status)}
    </>
  );
}
