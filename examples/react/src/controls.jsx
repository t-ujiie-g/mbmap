// The map's controls as a React toolbar along the bottom, from the same
// `mbmap/ui` controllers the plain-DOM examples draw as a column of buttons.
import { useEffect, useState, useSyncExternalStore } from "react";
import { createAttribution, createFullscreen, createGeolocation, createNavigation, createScale } from "mbmap/ui";

function useController(c) {
  return useSyncExternalStore(c.subscribe, () => c.state);
}

const LOCATION = { unavailable: "使えません", off: "現在地", waiting: "取得中…", active: "追跡中", "active-error": "取得できません", background: "現在地へ", "background-error": "取得できません" };

function Location({ map, geo }) {
  const g = useController(geo);
  const [at, setAt] = useState(null);
  useEffect(() => {
    if (!g.position) return setAt(null);
    const t = map.track(g.position.lngLat, setAt);
    return () => t.remove();
  }, [map, g.position]);
  if (!at) return null;
  const r = g.accuracyRadius;
  return (
    <svg className="react-location" style={{ left: at.x - r, top: at.y - r }} width={2 * r} height={2 * r} aria-hidden="true">
      <circle cx={r} cy={r} r={r} fill="rgba(26, 115, 232, 0.15)" />
      <circle cx={r} cy={r} r={6} fill="#1a73e8" stroke="#fff" strokeWidth={2} />
    </svg>
  );
}

function Toolbar({ c }) {
  const nav = useController(c.nav);
  const geo = useController(c.geo);
  const full = useController(c.full);
  const scale = useController(c.scale);
  const credits = useController(c.attribution);
  return (
    <>
      <div className="toolbar" role="toolbar" aria-label="地図の操作">
        <button aria-label="縮小" disabled={!nav.canZoomOut} onClick={() => c.nav.zoomOut()}>−</button>
        <span className="toolbar-zoom">z{nav.zoom.toFixed(1)}</span>
        <button aria-label="拡大" disabled={!nav.canZoomIn} onClick={() => c.nav.zoomIn()}>+</button>
        <button aria-label="北を上に" onClick={() => c.nav.resetNorth(true)}>
          <span style={{ display: "inline-block", transform: `rotate(${-nav.bearing}deg)` }}>N↑</span>
        </button>
        <button aria-label="最初の位置へ" onClick={() => c.nav.home()}>ホーム</button>
        <button aria-pressed={geo.status !== "off" && geo.status !== "unavailable"} data-status={geo.status} disabled={geo.status === "unavailable"} onClick={() => c.geo.trigger()}>
          {LOCATION[geo.status]}
        </button>
        <button aria-pressed={full.active} onClick={() => c.full.toggle()}>{full.active ? "戻す" : "全画面"}</button>
        <span className="toolbar-scale">
          <span style={{ width: scale.width }} />
          {scale.label}
        </span>
      </div>
      <div className="credits">{credits.text}</div>
    </>
  );
}

/** The toolbar over `map`, its controllers made once and destroyed with it. */
export function MapControls({ map }) {
  const [c] = useState(() => ({
    nav: createNavigation(map),
    geo: createGeolocation(map, { trackUserLocation: true }),
    full: createFullscreen(map, { container: document.documentElement }),
    scale: createScale(map, { maxWidth: 80 }),
    attribution: createAttribution(map),
  }));
  useEffect(() => {
    window.__controls = c;
    return () => Object.values(c).forEach((x) => x.destroy());
  }, [c]);
  return (
    <>
      <Location map={map} geo={c.geo} />
      <Toolbar c={c} />
    </>
  );
}
