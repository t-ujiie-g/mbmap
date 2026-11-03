// Measuring on the map with `mbmap/ui`'s controller and mbmap/geodesic's
// `measure` (GeographicLib on WGS 84): click to place vertices, double click or
// 「終える」 to finish. While it measures, clicks do not identify features.
import { measure } from "mbmap/geodesic";
import { createMeasurement, formatArea, formatLength } from "mbmap/ui";

export function createShowcaseMeasurement(map) {
  const m = createMeasurement(map, { measure });
  window.__measurement = m;
  return m;
}

/** Identifies the features under each click unless `measurement` is measuring; returns the function that stops it. */
export function identifyWhenIdle(map, identify, measurement) {
  const click = (e) => {
    if (!measurement.state.mode) void identify.identify(e.point);
  };
  map.on("click", click);
  return () => map.off("click", click);
}

/** The readout's rows: the length (or perimeter), the area, and the edges. */
export function measuredRows(s) {
  if (!s.mode) return [["—", "「距離」か「面積」を押して地図をクリック"]];
  const rows = [[s.mode === "area" ? "周囲" : "距離", formatLength(s.length)]];
  if (s.area !== null) rows.push(["面積", formatArea(s.area)]);
  rows.push(["区間", `${s.segments.length}`]);
  if (!s.finished) rows.push(["", "ダブルクリックで終える"]);
  return rows;
}

/** The operations as [label, action, enabled] for a state. */
export function measureActions(m, s) {
  return [
    ["距離", () => m.start("distance"), true],
    ["面積", () => m.start("area"), true],
    ["一つ戻す", () => m.undo(), s.positions.length > 0],
    ["終える", () => m.finish(), Boolean(s.mode) && !s.finished],
    ["消す", () => m.clear(), Boolean(s.mode)],
  ];
}

/** The tool in the panel for the plain-DOM examples: buttons in `#measure`, the readout in `#measured`. */
export function mountMeasurement(map) {
  const m = createShowcaseMeasurement(map);
  const bar = document.getElementById("measure");
  const dl = document.getElementById("measured");
  const draw = (s) => {
    bar.replaceChildren(
      ...measureActions(m, s).map(([label, f, enabled], i) => {
        const b = Object.assign(document.createElement("button"), { textContent: label, disabled: !enabled });
        if (i < 2) b.setAttribute("aria-pressed", String(s.mode === (i === 0 ? "distance" : "area")));
        b.addEventListener("click", f);
        return b;
      }),
    );
    dl.replaceChildren(...measuredRows(s).flatMap(([k, v]) => [Object.assign(document.createElement("dt"), { textContent: k }), Object.assign(document.createElement("dd"), { textContent: v })]));
  };
  m.subscribe(draw);
  draw(m.state);
  return m;
}
