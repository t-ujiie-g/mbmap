// The features under a click and the pointer's coordinates in React: every
// feature found listed (click one to select and highlight it) and a table of
// coordinates, from the controllers the plain-DOM examples draw differently.
import { useEffect, useState } from "react";
import { createIdentify } from "mbmap/ui";
import { createCoordinateReadout } from "../../shared/coordinates.js";
import { createShowcaseDraw } from "../../shared/draw.js";
import { createShowcaseMeasurement, identifyWhenIdle } from "../../shared/measure.js";
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
        <ol className="react-features">
          {s.features.map((f, i) => (
            <li key={i}>
              <button aria-pressed={i === s.index} onClick={() => identify.select(i)}>
                {f.layer.id}
                {f.properties.name ?? f.properties.knj ? `：${f.properties.name ?? f.properties.knj}` : ""}
              </button>
            </li>
          ))}
        </ol>
      )}
      <dl id="picked">{rows.map(([k, v], i) => [<dt key={`k${i}`}>{k}</dt>, <dd key={`v${i}`}>{v}</dd>])}</dl>
    </>
  );
}

function Coordinates({ c }) {
  const s = useController(c);
  return (
    <table className="react-coordinates">
      <caption>{s.source === "pointer" ? "ポインタ" : "中心"}の座標</caption>
      <tbody>
        {s.values.map((v) => (
          <tr key={v.id}>
            <th>{v.title}</th>
            <td>{v.text}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/**
 * The identify list, the coordinates table, the drawing, the measurement and its profile, their
 * controllers made once per map; clicks identify unless they measure or draw.
 */
export function useIdentify(map) {
  const [c, setC] = useState(null);
  useEffect(() => {
    if (!map) return;
    const next = { identify: createIdentify(map, { click: false }), coordinates: createCoordinateReadout(map), measurement: createShowcaseMeasurement(map) };
    next.draw = createShowcaseDraw(map, next.measurement);
    const stop = identifyWhenIdle(map, next.identify, () => next.measurement.state.mode || next.draw.state.mode);
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
  return c && { picked: <Picked identify={c.identify} />, coordinates: <Coordinates c={c.coordinates} />, measure: <Measure m={c.measurement} beforeStart={() => c.draw.setMode(null)} />, draw: <Draw draw={c.draw} />, profile: <Profile map={map} profile={c.profile} /> };
}
