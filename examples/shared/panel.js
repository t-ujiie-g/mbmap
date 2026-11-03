// The panel's basemaps, layer list and legend drawn with plain DOM from
// `mbmap/ui`'s controllers (the React example draws them its own way).
import { createBasemaps, createLayerList, createLegend } from "mbmap/ui";
import { BASEMAPS, LAYER_GROUPS, LAYER_TITLES, createStyle, legendLabel } from "./style.js";

/** CSS for a straight RGBA color in 0 to 1. */
export const css = ([r, g, b, a]) => `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${a})`;

/**
 * The three controllers of the showcase's panel: groups of layers, the legend, and basemaps whose
 * styles are made for the current `mode()` and `places()` with the hidden groups left out.
 */
export function panelControllers(map, mode, places) {
  const layers = createLayerList(map, { groups: LAYER_GROUPS.map((g) => ({ id: g.name, layers: g.ids })) });
  const hidden = () => new Set(layers.state.items.filter((i) => i.layers.length > 0 && !i.visible).map((i) => i.id));
  const legend = createLegend(map, { title: (l) => LAYER_TITLES[l.id] ?? l.id, label: legendLabel });
  const basemaps = createBasemaps(map, {
    basemaps: BASEMAPS.map((b) => ({ ...b, style: () => createStyle(mode(), hidden(), places(), b.id) })),
    active: "map",
  });
  window.__panel = { layers, legend, basemaps };
  return { layers, legend, basemaps, hidden };
}

function swatch(type, paint) {
  const s = document.createElement("span");
  s.className = `swatch swatch-${type}`;
  s.style.setProperty("--color", css(paint.color));
  return s;
}

/** Draws the controllers into `#basemaps`, `#layers` and `#legend`. */
export function mountPanel(c) {
  const draw = () => {
    document.getElementById("basemaps").replaceChildren(
      ...c.basemaps.state.basemaps.map((b) => {
        const button = Object.assign(document.createElement("button"), { textContent: b.title });
        button.setAttribute("aria-pressed", String(b.id === c.basemaps.state.active));
        button.addEventListener("click", () => c.basemaps.select(b.id));
        return button;
      }),
    );
    document.getElementById("layers").replaceChildren(
      ...c.layers.state.items.map((item) => {
        const button = Object.assign(document.createElement("button"), { textContent: item.title });
        button.setAttribute("aria-pressed", String(item.visible));
        button.disabled = item.layers.length === 0;
        button.classList.toggle("out-of-range", !item.inRange);
        button.addEventListener("click", () => c.layers.toggle(item.id));
        return button;
      }),
    );
    const entries = c.legend.state.entries.filter((e) => e.visible && e.items.length > 0);
    document.getElementById("legend").replaceChildren(
      ...entries.map((e) => {
        const row = document.createElement("li");
        const title = Object.assign(document.createElement("span"), { className: "legend-title", textContent: e.title });
        if (e.kind === "single") {
          row.append(swatch(e.type, e.items[0].paint), title);
        } else {
          const items = document.createElement("ul");
          items.append(...e.items.map((i) => Object.assign(document.createElement("li"), { textContent: ` ${i.label}` })));
          e.items.forEach((i, k) => items.children[k].prepend(swatch(e.type, i.paint)));
          row.append(title, Object.assign(document.createElement("span"), { textContent: ` (${e.property})` }), items);
        }
        return row;
      }),
    );
  };
  for (const ctl of [c.basemaps, c.layers, c.legend]) ctl.subscribe(draw);
  draw();
}
