// The panel's basemaps, layer list and legend in React: radio buttons,
// checkboxes and a collapsible legend over the same controllers the plain-DOM
// examples draw as buttons (shared/panel.js makes them).
import { css } from "../../shared/panel.js";
import { useController } from "./use-controller.js";

export function Basemaps({ c }) {
  const s = useController(c);
  return (
    <div role="radiogroup" aria-label="背景地図" className="react-choices">
      {s.basemaps.map((b) => (
        <label key={b.id}>
          <input type="radio" name="basemap" checked={s.active === b.id} onChange={() => c.select(b.id)} /> {b.title}
        </label>
      ))}
    </div>
  );
}

export function LayerChecklist({ c }) {
  const s = useController(c);
  return (
    <div className="react-choices">
      {s.items.map((i) => (
        <label key={i.id} className={i.inRange ? "" : "out-of-range"}>
          <input
            type="checkbox"
            checked={i.visible}
            disabled={i.layers.length === 0}
            ref={(el) => el && (el.indeterminate = i.mixed)}
            onChange={() => c.toggle(i.id)}
          />{" "}
          {i.title}
        </label>
      ))}
    </div>
  );
}

function Swatch({ type, color }) {
  const style = { background: css(color) };
  if (type === "line") return <svg width="18" height="8"><line x1="1" y1="4" x2="17" y2="4" stroke={css(color)} strokeWidth="3" /></svg>;
  if (type === "circle") return <svg width="12" height="12"><circle cx="6" cy="6" r="5" fill={css(color)} /></svg>;
  if (type === "symbol") return <b style={{ color: css(color) }}>Aa</b>;
  return <span className="react-swatch" style={style} />;
}

export function Legend({ c }) {
  const s = useController(c);
  const entries = s.entries.filter((e) => e.visible && e.items.length > 0);
  return (
    <details open className="react-legend">
      <summary>凡例（{entries.length}）</summary>
      <table>
        <tbody>
          {entries.flatMap((e) =>
            e.items.map((i, k) => (
              <tr key={`${e.id}/${k}`}>
                <td><Swatch type={e.type} color={i.paint.color} /></td>
                <td>{k === 0 ? e.title : ""}</td>
                <td>{e.kind === "single" ? "" : i.label}</td>
              </tr>
            )),
          )}
        </tbody>
      </table>
    </details>
  );
}
