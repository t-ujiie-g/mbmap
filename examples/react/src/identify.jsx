// The features under a click (every one listed: click one to highlight it) and the pointer's
// coordinates in React, from the controllers the plain-DOM examples draw with the DOM.
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { createIdentify } from "mbmap/ui";
import { createCoordinateReadout } from "../../shared/coordinates.js";
import { createShowcaseDraw } from "../../shared/draw.js";
import { createAnalysis, routeAnalysisClicks } from "../../shared/analyze.js";
import { createShowcaseMeasurement, identifyWhenIdle } from "../../shared/measure.js";
import { Analysis } from "./analysis.jsx";
import { createShowcaseProfile } from "../../shared/profile.js";
import { selectedRows } from "../../shared/pick.js";
import { Draw } from "./draw.jsx";
import { Measure, Profile } from "./measure.jsx";
import { useController } from "./use-controller.js";

function Picked({ identify }) {
  const s = useController(identify);
  const rows = selectedRows(s) ?? [["—", s.point ? "何もありません" : "地図をクリック"]];
  useEffect(() => {
    if (s.point && !s.loading) window.__picked = rows;
  });
  return (
    <>
      {s.features.length > 1 && (
        <div className="chips picked-nav">
          {s.features.map((f, i) => (
            <button key={i} aria-pressed={i === s.index} onClick={() => identify.select(i)}>
              {f.layer.id}
              {f.properties.name ?? f.properties.knj ? `：${f.properties.name ?? f.properties.knj}` : ""}
            </button>
          ))}
        </div>
      )}
      <dl id="picked" className="rows">{rows.map(([k, v], i) => [<dt key={`k${i}`}>{k}</dt>, <dd key={`v${i}`}>{v}</dd>])}</dl>
    </>
  );
}

function Coordinates({ c, status }) {
  const s = useController(c);
  return createPortal(
    <dl className="coordinates">
      {s.values.map((v) => <div key={v.id}><dt>{v.title}</dt><dd>{v.text}</dd></div>)}
    </dl>,
    status,
  );
}

/**
 * The identify list, the coordinates table, the drawing, the measurement and its profile, the
 * analysis tab, their controllers made once per map; clicks identify unless they measure, draw or pick.
 */
export function useIdentify(map, status) {
  const [c, setC] = useState(null);
  useEffect(() => {
    if (!map) return;
    const next = { identify: createIdentify(map, { click: false }), coordinates: createCoordinateReadout(map), measurement: createShowcaseMeasurement(map) };
    next.draw = createShowcaseDraw(map, next.measurement);
    next.analysis = createAnalysis(map, () => {
      next.draw.setMode(null);
      next.measurement.clear();
    });
    const stopClicks = routeAnalysisClicks(map, next.analysis, [next.measurement, next.draw]);
    const stopIdentify = identifyWhenIdle(map, next.identify, () => next.measurement.state.mode || next.draw.state.mode || next.analysis.state.picking);
    const stop = () => {
      stopClicks();
      stopIdentify();
    };
    const profile = createShowcaseProfile(next.measurement);
    next.profile = profile.profile;
    window.__identify = next.identify;
    setC(next);
    return () => {
      stop();
      profile.stop();
      Object.values(next).forEach((x) => x.destroy());
    };
  }, [map]);
  return c && { picked: <Picked identify={c.identify} />, coordinates: status && <Coordinates c={c.coordinates} status={status} />, measure: <Measure m={c.measurement} beforeStart={() => c.draw.setMode(null)} />, draw: <Draw draw={c.draw} />, profile: <Profile map={map} profile={c.profile} />, analysis: <Analysis map={map} a={c.analysis} /> };
}
