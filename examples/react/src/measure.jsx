// Measuring in React: the same controllers and readout rows as the plain-DOM
// examples, the operations as a segmented toolbar and the profile's figures as a caption.
import { useEffect, useRef } from "react";
import { measureActions, measuredRows } from "../../shared/measure.js";
import { CHART, chartOf, distanceAt, profileRows, trackProfile } from "../../shared/profile.js";
import { useController } from "./use-controller.js";

export function Measure({ m, beforeStart }) {
  const s = useController(m);
  return (
    <>
      <div id="measure" className="react-measure" role="toolbar" aria-label="計測">
        {measureActions(m, s, beforeStart).map(([label, f, enabled], i) => (
          <button key={label} disabled={!enabled} aria-pressed={i < 2 ? s.mode === (i === 0 ? "distance" : "area") : undefined} onClick={f}>
            {label}
          </button>
        ))}
      </div>
      <dl id="measured">{measuredRows(s).map(([k, v], i) => [<dt key={`k${i}`}>{k}</dt>, <dd key={`v${i}`}>{v}</dd>])}</dl>
    </>
  );
}

/** The profile as an SVG chart with the figures as a caption line; the place pointed at is a dot on the map. */
export function Profile({ map, profile }) {
  const s = useController(profile);
  const ref = useRef(null);
  useEffect(() => trackProfile(map, profile, document.body), [map, profile]);
  const c = chartOf(s);
  return (
    <figure id="profile" className="react-profile">
      {c && (
        <svg
          ref={ref}
          className="profile-chart"
          viewBox={`0 0 ${CHART.width} ${CHART.height}`}
          role="img"
          aria-label="断面図"
          onPointerMove={(e) => profile.highlight(distanceAt(s, ref.current, e.clientX))}
          onPointerLeave={() => profile.highlight(null)}
        >
          <path className="profile-area" d={c.area} />
          <path className="profile-line" d={c.line} />
          <text className="profile-label" x={CHART.pad + 2} y={12}>{c.top}</text>
          <text className="profile-label" x={CHART.pad + 2} y={CHART.height - 8}>{c.bottom}</text>
          {c.at && <circle className="profile-at" cx={c.at.x} cy={c.at.y} r={3.5} />}
        </svg>
      )}
      <figcaption>
        {profileRows(s).map(([k, v], i) => (
          <span key={i}>{k && <b>{k} </b>}{v}</span>
        ))}
      </figcaption>
    </figure>
  );
}
