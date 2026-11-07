// The page around the map for the plain-DOM examples (the React example writes the same markup in
// JSX): a panel with the search and five tabs, the view's buttons, and a status bar. The markup is
// constant; everything that comes from data goes in later through `textContent`.
import { icon } from "./icons.js";

/** The panel's tabs as [id, label]. */
export const TABS = [["explore", "探す"], ["layers", "レイヤー"], ["draw", "作図"], ["measure", "計測"], ["data", "データ"]];

/** The three ways the showcase is written as [path, label]. */
export const VARIANTS = [["html", "HTML"], ["element", "Element"], ["react", "React"]];

const TAB_BODIES = {
  explore: `
    <h2>移動</h2><div id="destinations" class="chips"></div>
    <h2>クリックした地物</h2><dl id="picked" class="rows"><dt>—</dt><dd>地図をクリック</dd></dl>
    <h2>中心から 5 km 以内の地点</h2><ul id="near" class="plain-list"></ul>
    <h2>カメラ</h2><dl id="camera" class="rows"></dl>`,
  layers: `
    <h2>背景地図</h2><div id="basemaps" class="segmented"></div>
    <h2>レイヤー</h2><div id="layers" class="toggles"></div>
    <details class="legend"><summary>凡例</summary><ul id="legend"></ul></details>`,
  draw: `
    <h2>形</h2><div id="draw-modes" class="chips"></div>
    <div id="draw-actions" class="chips"></div>
    <p id="drawn" class="hint"></p>
    <div id="draw-fields" hidden></div>`,
  measure: `
    <h2>距離と面積</h2><div id="measure" class="chips"></div>
    <dl id="measured" class="rows"></dl>
    <h2>断面図</h2><figure id="profile"></figure>`,
  data: `
    <h2>読み込み</h2><div id="data"></div>
    <h2>Web サービス</h2><div id="services"></div>
    <h2>地点の一覧</h2><div id="table"></div>
    <div class="chips"><button id="marker">中心に印を置く</button></div>`,
};

/** Shows tab `id`, in the markup both ways of drawing the panel share. */
function showTab(root, id) {
  for (const b of root.querySelectorAll(".tabs button")) b.setAttribute("aria-selected", String(b.dataset.tab === id));
  for (const p of root.querySelectorAll("[role=tabpanel]")) p.hidden = p.dataset.panel !== id;
}

/** Adds the panel, the view's buttons and the status bar to the page; `current` is this example's path in VARIANTS. */
export function mountShell(current) {
  const panel = document.createElement("aside");
  panel.className = "panel";
  const card = document.createElement("div");
  card.className = "panel-card";
  const brand = document.createElement("header");
  brand.className = "brand";
  const logo = Object.assign(document.createElement("a"), { className: "logo", href: "../", textContent: "mbmap" });
  const variants = document.createElement("nav");
  variants.className = "variants";
  variants.setAttribute("aria-label", "書き方");
  for (const [path, label] of VARIANTS) {
    const a = Object.assign(document.createElement("a"), { href: `../${path}/`, textContent: label });
    if (path === current) a.setAttribute("aria-current", "page");
    variants.append(a);
  }
  const collapse = Object.assign(document.createElement("button"), { className: "collapse", title: "パネルを畳む" });
  collapse.setAttribute("aria-label", "パネルを畳む");
  collapse.append(icon("chevron"));
  collapse.addEventListener("click", () => card.classList.toggle("collapsed"));
  brand.append(logo, variants, collapse);

  const search = Object.assign(document.createElement("div"), { id: "search" });
  const tabs = document.createElement("div");
  tabs.className = "tabs";
  tabs.setAttribute("role", "tablist");
  const body = document.createElement("div");
  body.className = "tab-body";
  for (const [id, label] of TABS) {
    const b = Object.assign(document.createElement("button"), { textContent: label });
    b.dataset.tab = id;
    b.setAttribute("role", "tab");
    b.addEventListener("click", () => showTab(card, id));
    tabs.append(b);
    const section = document.createElement("section");
    section.dataset.panel = id;
    section.setAttribute("role", "tabpanel");
    section.innerHTML = TAB_BODIES[id];
    body.append(section);
  }
  card.append(brand, search, tabs, body);
  panel.append(card);

  const actions = document.createElement("div");
  actions.className = "map-actions";
  const modes = Object.assign(document.createElement("div"), { id: "modes", className: "segmented" });
  for (const m of ["2d", "3d"]) {
    const b = Object.assign(document.createElement("button"), { textContent: m.toUpperCase() });
    b.dataset.mode = m;
    modes.append(b);
  }
  const save = Object.assign(document.createElement("button"), { id: "save", title: "画像を保存" });
  save.setAttribute("aria-label", "画像を保存");
  save.append(icon("camera"));
  actions.append(modes, save);

  const status = document.createElement("div");
  status.className = "statusbar";
  document.body.append(panel, actions, status);
  showTab(card, "explore");
  return { status };
}
