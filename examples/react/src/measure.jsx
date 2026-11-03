// Measuring in React: the same controller and readout rows as the plain-DOM
// examples, the operations as a segmented toolbar.
import { measureActions, measuredRows } from "../../shared/measure.js";
import { useController } from "./use-controller.js";

export function Measure({ m }) {
  const s = useController(m);
  return (
    <>
      <div id="measure" className="react-measure" role="toolbar" aria-label="計測">
        {measureActions(m, s).map(([label, f, enabled], i) => (
          <button key={label} disabled={!enabled} aria-pressed={i < 2 ? s.mode === (i === 0 ? "distance" : "area") : undefined} onClick={f}>
            {label}
          </button>
        ))}
      </div>
      <dl id="measured">{measuredRows(s).map(([k, v], i) => [<dt key={`k${i}`}>{k}</dt>, <dd key={`v${i}`}>{v}</dd>])}</dl>
    </>
  );
}
