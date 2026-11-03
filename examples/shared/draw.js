// Drawing with mbmap/draw (clicks as terra-draw's; circles on the ellipsoid
// through mbmap/geodesic). Drawing and measuring exclude each other, and keys
// go to the drawing unless they belong to an IME composition or a text field.
import { createDraw } from "mbmap/draw";
import * as geodesic from "mbmap/geodesic";

export const DRAW_MODES = [["point", "点"], ["linestring", "線"], ["polygon", "多角形"], ["rectangle", "矩形"], ["circle", "円"], ["freehand", "フリーハンド"]];

/** The drawing over `map`; choosing a mode clears `measurement`'s. */
export function createShowcaseDraw(map, measurement) {
  const draw = createDraw(map, { geodesic });
  const setMode = draw.setMode.bind(draw);
  draw.setMode = (mode) => {
    if (mode) measurement.clear();
    setMode(mode);
  };
  window.__draw = draw;
  return draw;
}

/** Enter finishes, Escape cancels, ⌘Z / Ctrl+Z undoes and with Shift redoes. */
export function onDrawKey(draw, e) {
  if (e.isComposing || e.keyCode === 229 || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target?.tagName ?? "")) return;
  if (e.key === "Enter" && draw.state.mode) draw.finish();
  else if (e.key === "Escape" && draw.state.mode) draw.cancel();
  else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z") {
    e.preventDefault();
    if (e.shiftKey) draw.redo();
    else draw.undo();
  }
}

/** The operations as [label, action, enabled]. */
export function drawActions(draw, s) {
  return [
    ["一つ戻す", () => draw.undo(), s.canUndo],
    ["やり直す", () => draw.redo(), s.canRedo],
    ["確定", () => draw.finish(), s.vertices.length > 0],
    ["やめる", () => draw.setMode(null), Boolean(s.mode)],
    ["全部消す", () => draw.clear(), s.features.length > 0],
    ["GeoJSON で保存", () => saveGeoJSON(s.features), s.features.length > 0],
  ];
}

/** What the readout says: how many of each shape, and what the clicks do now. */
export function drawnText(s) {
  const counts = DRAW_MODES.map(([m, label]) => [label, s.features.filter((f) => f.properties.mode === m).length]).filter(([, n]) => n > 0);
  const hint = {
    point: "クリックで点を置く",
    linestring: "クリックで頂点、最後の頂点をもう一度クリックで終わる",
    polygon: "クリックで頂点、最初の頂点をクリックで閉じる",
    rectangle: "2 つの角をクリック",
    circle: "中心と半径の位置をクリック",
    freehand: "クリックで始め、動かして、クリックで閉じる",
  }[s.mode] ?? "形を選ぶ";
  return { counts: counts.map(([l, n]) => `${l} ${n}`).join("、") || "まだありません", hint };
}

function saveGeoJSON(features) {
  const blob = new Blob([JSON.stringify({ type: "FeatureCollection", features }, null, 2)], { type: "application/geo+json" });
  const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: "drawing.geojson" });
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

/** The tool in the panel for the plain-DOM examples: modes in `#draw-modes`, operations in `#draw-actions`, the readout in `#drawn`. */
export function mountDraw(map, measurement) {
  const draw = createShowcaseDraw(map, measurement);
  const modes = document.getElementById("draw-modes");
  const actions = document.getElementById("draw-actions");
  const readout = document.getElementById("drawn");
  const button = (label, f, enabled = true) => {
    const b = Object.assign(document.createElement("button"), { textContent: label, disabled: !enabled });
    b.addEventListener("click", f);
    return b;
  };
  const show = (s) => {
    modes.replaceChildren(
      ...DRAW_MODES.map(([m, label]) => {
        const b = button(label, () => draw.setMode(s.mode === m ? null : m));
        b.setAttribute("aria-pressed", String(s.mode === m));
        return b;
      }),
    );
    actions.replaceChildren(...drawActions(draw, s).map(([label, f, enabled]) => button(label, f, enabled)));
    const t = drawnText(s);
    readout.textContent = `${t.counts}。${t.hint}`;
  };
  draw.subscribe(show);
  show(draw.state);
  document.addEventListener("keydown", (e) => onDrawKey(draw, e));
  return draw;
}
