// The panel's basemaps, layer list and legend in React, over the controllers shared/panel.js makes.
import { css } from "../../shared/panel.js";
import { useController } from "./use-controller.js";

export function Basemaps({ c }) {
  const s = useController(c);
  return (
    <div id="basemaps" className="segmented">
      {s.basemaps.map((b) => <button key={b.id} aria-pressed={s.active === b.id} onClick={() => c.select(b.id)}>{b.title}</button>)}
    </div>
  );
}

export function LayerChecklist({ c }) {
  const s = useController(c);
  return (
    <div id="layers" className="toggles">
      {s.items.map((i) => (
        <label key={i.id} className={i.inRange ? "" : "out-of-range"}>
          {i.title}
          <input type="checkbox" checked={i.visible} disabled={i.layers.length === 0} ref={(el) => el && (el.indeterminate = i.mixed)} onChange={() => c.toggle(i.id)} />
        </label>
      ))}
    </div>
  );
}

const Swatch = ({ type, color }) => <span className={`swatch swatch-${type}`} style={{ "--color": css(color) }} />;

export function Legend({ c }) {
  const s = useController(c);
  const entries = s.entries.filter((e) => e.visible && e.items.length > 0);
  return (
    <details className="legend">
      <summary>凡例</summary>
      <ul id="legend">
        {entries.map((e) =>
          e.kind === "single" ? (
            <li key={e.id}><Swatch type={e.type} color={e.items[0].paint.color} /><span>{e.title}</span></li>
          ) : (
            <li key={e.id}>
              <span>{e.title}</span>
              <ul>{e.items.map((i, k) => <li key={k}><Swatch type={e.type} color={i.paint.color} /> {i.label}</li>)}</ul>
            </li>
          ),
        )}
      </ul>
    </details>
  );
}
