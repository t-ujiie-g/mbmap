// The analysis tab in React: the same tools, buttons and readouts as the plain-DOM examples.
import { analysisActions, analysisRows } from "../../shared/analyze.js";
import { useController } from "./use-controller.js";

const TOOLS = [["cells", "階級区分図"], ["route", "道路での経路"], ["sight", "見通しと可視域"]];

export function Analysis({ map, a }) {
  const s = useController(a);
  const actions = analysisActions(a, s, () => map.getCenter());
  const rows = analysisRows(s);
  return (
    <>
      {TOOLS.map(([key, title]) => [
        <h2 key={`h${key}`}>{title}</h2>,
        <div key={`b${key}`} id={`analysis-${key}`} className="chips">
          {actions[key].map(([label, f, pressed, enabled]) => (
            <button key={label} disabled={!enabled} aria-pressed={pressed} onClick={f}>
              {label}
            </button>
          ))}
        </div>,
        <dl key={`r${key}`} id={`analysis-${key}-rows`} className="rows">
          {rows[key].map(([k, v], i) => [<dt key={`k${i}`}>{k}</dt>, <dd key={`v${i}`}>{v}</dd>])}
        </dl>,
      ])}
      <p id="analysis-error" className="hint" hidden={!rows.error}>{rows.error ?? ""}</p>
    </>
  );
}
