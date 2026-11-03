// Drawing in React: the modes as a segmented toolbar, the shapes drawn as a list
// (select or delete each) and the selected one's fields, from the plain-DOM examples' controller.
import { useEffect } from "react";
import { DRAW_MODES, FIELDS, drawActions, drawnText, fieldValue, onDrawKey } from "../../shared/draw.js";
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
          <li key={f.id} aria-current={s.selection.includes(f.id)}>
            <button className="react-link" onClick={(e) => (draw.state.mode !== "select" && draw.setMode("select"), draw.select(f.id, e.shiftKey))}>
              {DRAW_MODES.find(([m]) => m === f.properties.mode)?.[1]} {f.properties.name ?? <code>{f.id}</code>}
            </button>
            <button aria-label={`${f.id} を消す`} onClick={() => draw.remove(f.id)}>×</button>
          </li>
        ))}
      </ol>
      {s.selection.length === 1 && (
        <div id="draw-fields" key={s.selected}>
          {FIELDS.map(([key, label]) => (
            <label key={key}>
              {label}
              <input name={key} defaultValue={fieldValue(s, key)} onBlur={(e) => draw.setProperties(s.selected, { [key]: e.target.value || null })} onKeyDown={(e) => e.key === "Enter" && !e.nativeEvent.isComposing && e.nativeEvent.keyCode !== 229 && e.currentTarget.blur()} />
            </label>
          ))}
        </div>
      )}
    </>
  );
}
