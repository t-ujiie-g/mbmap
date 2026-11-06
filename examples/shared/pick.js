// What the panel shows of a clicked feature (its layer, then its name, GSI's
// `knj` or the places' `name`, or its first properties), and the places'
// hover highlight.
import { createIdentify } from "mbmap/ui";
import { showRows } from "./readout.js";

/** Rows of [label, value] for the topmost of `features`, or null when there is none. */
export function describeFeature(features) {
  const f = features[0];
  if (!f) return null;
  const p = f.properties;
  const name = p.name ?? p.knj;
  const rest = Object.entries(p).filter(([k]) => k !== "name" && k !== "knj").slice(0, name === undefined ? 4 : 2);
  return [["レイヤー", f.layer.id], ...(name === undefined ? [] : [["名前", String(name)]]), ...rest.map(([k, v]) => [k, String(v)])];
}

/**
 * Highlights the place under the mouse through its feature state (`hover`, read by the
 * places layer's paint; ids are the places' names, `promoteId`) and shows a pointer there.
 */
export function hoverPlaces(map) {
  let hovered = null;
  const leave = () => {
    if (hovered !== null) map.setFeatureState({ source: "places", id: hovered }, { hover: false });
    hovered = null;
    map.getCanvas().style.cursor = "";
  };
  map.on("mousemove", "places", (e) => {
    const id = e.features[0].id;
    if (id === hovered) return;
    leave();
    hovered = id;
    map.setFeatureState({ source: "places", id }, { hover: true });
    map.getCanvas().style.cursor = "pointer";
    window.__hovered = id;
  });
  map.on("mouseleave", "places", leave);
}

/** The selected feature of an identify controller's state as rows (`describeFeature`). */
export function selectedRows(state) {
  const f = state.features[state.index];
  return f ? describeFeature([f]) : null;
}

/**
 * The features under each click from `mbmap/ui`'s identify controller, drawn into `#picked`: the
 * selected one's rows and buttons to step through the others (the selection is highlighted). The
 * page calls `identify` (it skips clicks that measure).
 */
export function mountIdentify(map) {
  const identify = createIdentify(map, { click: false });
  const dl = document.getElementById("picked");
  const nav = document.createElement("div");
  nav.className = "picked-nav";
  dl.before(nav);
  const step = (label, f) => {
    const b = Object.assign(document.createElement("button"), { textContent: label });
    b.addEventListener("click", f);
    return b;
  };
  const prev = step("◀", () => identify.previous());
  const next = step("▶", () => identify.next());
  const count = document.createElement("span");
  nav.append(prev, count, next);
  identify.subscribe((s) => {
    nav.hidden = s.features.length < 2;
    count.textContent = `${s.index + 1} / ${s.features.length}`;
    if (s.loading) return;
    const rows = selectedRows(s) ?? [["—", "何もありません"]];
    showRows(dl, rows);
    window.__picked = rows;
  });
  nav.hidden = true;
  window.__identify = identify;
  return identify;
}
