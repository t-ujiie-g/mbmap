// Drawing in React: the modes as a segmented toolbar, the shapes drawn as a
// list with a button to delete each, from the same controller as the plain-DOM examples.
import { useEffect } from "react";
import { DRAW_MODES, drawActions, drawnText, onDrawKey } from "../../shared/draw.js";
import { useController } from "./use-controller.js";

export function Draw({ draw }) {
  const s = useController(draw);
  useEffect(() => {
    const key = (e) => onDrawKey(draw, e);
    document.addEventListener("keydown", key);
    return () => document.removeEventListener("keydown", key);
  }, [draw]);
  const t = drawnText(s);
  return (
    <>
      <div id="draw-modes" className="react-measure" role="toolbar" aria-label="作図">
        {DRAW_MODES.map(([m, label]) => (
          <button key={m} aria-pressed={s.mode === m} onClick={() => draw.setMode(s.mode === m ? null : m)}>{label}</button>
        ))}
      </div>
      <div id="draw-actions">
        {drawActions(draw, s).map(([label, f, enabled]) => <button key={label} disabled={!enabled} onClick={f}>{label}</button>)}
      </div>
      <p id="drawn" className="react-hint">{t.hint}</p>
      <ol className="react-drawn">
        {s.features.map((f) => (
          <li key={f.id}>
            {DRAW_MODES.find(([m]) => m === f.properties.mode)?.[1]} <code>{f.id}</code>
            <button aria-label={`${f.id} を消す`} onClick={() => draw.remove(f.id)}>×</button>
          </li>
        ))}
      </ol>
    </>
  );
}
