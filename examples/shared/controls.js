// The map's controls drawn with plain DOM from `mbmap/ui`'s controllers (the
// React example draws the same controllers its own way): zoom, compass, home,
// location, full screen, a scale bar and the attributions.
import { createAttribution, createFullscreen, createGeolocation, createNavigation, createScale } from "mbmap/ui";

const LOCATION_LABELS = {
  unavailable: "現在地は使えません",
  off: "現在地を表示",
  waiting: "現在地を取得中",
  active: "現在地を追跡中",
  "active-error": "現在地を取得できません",
  background: "現在地へ戻る",
  "background-error": "現在地を取得できません",
};

function button(label, onClick) {
  const b = document.createElement("button");
  b.type = "button";
  b.setAttribute("aria-label", label);
  b.title = label;
  b.addEventListener("click", onClick);
  return b;
}

/** Controls over `map` in `parent` (which covers the map); returns their removal. */
export function mountControls(map, parent) {
  const nav = createNavigation(map);
  const geo = createGeolocation(map, { trackUserLocation: true });
  const full = createFullscreen(map, { container: document.documentElement });
  const scale = createScale(map, { maxWidth: 120 });
  const attribution = createAttribution(map);
  const controllers = [nav, geo, full, scale, attribution];

  const box = document.createElement("div");
  box.className = "controls";
  const zoomIn = button("拡大", () => nav.zoomIn());
  zoomIn.textContent = "+";
  const zoomOut = button("縮小", () => nav.zoomOut());
  zoomOut.textContent = "−";
  const compass = button("北を上に", () => nav.resetNorth(true));
  const needle = document.createElement("span");
  needle.className = "needle";
  needle.textContent = "↑";
  compass.append(needle);
  const home = button("最初の位置へ", () => nav.home());
  home.textContent = "⌂";
  const locate = button(LOCATION_LABELS.off, () => geo.trigger());
  locate.textContent = "◎";
  const fullscreen = button("全画面", () => full.toggle());
  fullscreen.textContent = "⛶";
  box.append(zoomIn, zoomOut, compass, home, locate, fullscreen);

  const bar = document.createElement("div");
  bar.className = "scale";
  const credits = document.createElement("div");
  credits.className = "credits";
  // The user's location: a dot with its accuracy circle, kept on its place by `track`.
  const dot = document.createElement("div");
  dot.className = "location";
  dot.hidden = true;
  parent.append(box, bar, credits, dot);
  let tracker = null;

  const draw = () => {
    const n = nav.state;
    zoomIn.disabled = !n.canZoomIn;
    zoomOut.disabled = !n.canZoomOut;
    needle.style.transform = `rotateX(${n.pitch}deg) rotateZ(${-n.bearing}deg)`;
    const g = geo.state;
    locate.disabled = g.status === "unavailable";
    locate.dataset.status = g.status;
    locate.setAttribute("aria-pressed", String(g.status !== "off" && g.status !== "unavailable"));
    locate.title = LOCATION_LABELS[g.status];
    locate.setAttribute("aria-label", LOCATION_LABELS[g.status]);
    dot.hidden = !g.position;
    dot.style.setProperty("--accuracy", `${g.accuracyRadius}px`);
    if (g.position && !tracker) tracker = map.track(g.position.lngLat, ({ x, y }) => (dot.style.transform = `translate(${x}px, ${y}px)`));
    else if (g.position) tracker.setLngLat(g.position.lngLat);
    else if (tracker) (tracker.remove(), (tracker = null));
    fullscreen.setAttribute("aria-pressed", String(full.state.active));
    document.documentElement.classList.toggle("pseudo-fullscreen", full.state.pseudo && full.state.active);
    bar.style.width = `${scale.state.width}px`;
    bar.textContent = scale.state.label;
    credits.textContent = attribution.state.text;
  };
  const offs = controllers.map((c) => c.subscribe(draw));
  map.on("load", draw);
  draw();
  window.__controls = { nav, geo, full, scale, attribution, elements: { box, bar, credits, dot, locate } };
  return () => {
    offs.forEach((off) => off());
    controllers.forEach((c) => c.destroy());
    tracker?.remove();
    box.remove();
    bar.remove();
    credits.remove();
    dot.remove();
  };
}
