// PLATEAU's LOD2 buildings of Chiyoda as 3D Tiles (mbmap/3d's tilesLayer) over GSI's vector map; a click
// shows the building's attributes. `?local=1` reads the bench fixture (the tiles around Tokyo Station).
import { Map } from "mbmap";
import { tilesLayer } from "mbmap/3d";
import { GSI_LAYERS } from "../shared/layers.js";
import { BUILDINGS_3D, gsiSource } from "../shared/style.js";

const local = new URLSearchParams(location.search).get("local") === "1";
const TILESET = local
  ? new URL("../../bench/fixtures/plateau-chiyoda/tileset.json", location.href).href
  : "https://assets.cms.plateau.reearth.io/assets/72/e900e5-938c-4376-a9de-a124b270880c/13101_chiyoda-ku_pref_2025_citygml_1_op_bldg_3dtiles_13101_chiyoda-ku_lod2_no_texture/tileset.json";
// PLATEAU's heights are above the ellipsoid; the geoid lies 36.7 m above it at Tokyo Station.
const GEOID = -36.7;

const PLACES = [
  ["東京駅", { center: [139.7671, 35.6812], zoom: 16.5, pitch: 60, bearing: -20 }],
  ["丸の内", { center: [139.7638, 35.6829], zoom: 17, pitch: 55, bearing: 60 }],
  ["大手町", { center: [139.7651, 35.6868], zoom: 16.5, pitch: 60, bearing: 160 }],
  ["皇居外苑", { center: [139.7565, 35.6802], zoom: 15.5, pitch: 50, bearing: 80 }],
];

/** The attributes shown first, as [key, label, unit]. */
const SHOWN = [
  ["gml:name", "名称"],
  ["bldg:usage", "用途"],
  ["bldg:class", "種類"],
  ["bldg:measuredHeight", "計測高さ", " m"],
  ["bldg:storeysAboveGround", "地上階数"],
  ["bldg:storeysBelowGround", "地下階数"],
  ["uro:BuildingDetailAttribute_uro:fireproofStructureType", "耐火構造"],
  ["uro:BuildingDetailAttribute_uro:districtsAndZonesType", "用途地域"],
  ["uro:lodType", "LOD"],
  ["uro:BuildingIDAttribute_uro:buildingID", "建物 ID"],
];

const style = {
  version: 8,
  sources: { gsi: gsiSource() },
  layers: [
    { id: "background", type: "background", paint: { "background-color": "#f5f3ee" } },
    ...GSI_LAYERS.flatMap((l) => (l.id === "building-outline" ? [] : l.id === "building" ? [{ ...BUILDINGS_3D, layout: { visibility: "none" } }] : [l])),
  ],
};

const map = new Map({ container: "map", style, ...PLACES[0][1], attributionControl: false });
const layer = tilesLayer({ id: "plateau", url: TILESET, height: GEOID });
window.__map = map;
window.__layer = layer;

const status = document.getElementById("status");
const feature = document.getElementById("feature");
layer.ready.catch((e) => (status.textContent = `PLATEAU のタイルセットを読めませんでした：${e.message}`));
map.on("error", (e) => console.error(e.error));

function showStatus() {
  if (!map.getLayer("plateau")) status.textContent = "地図の押し出しの建物（高さは国土地理院の建物の種類から仮に決めたもの）";
  else if (layer.selected.length) status.textContent = `描いているタイル ${layer.selected.length}${layer.idle ? "" : "（読み込み中）"}`;
}

/** Shows PLATEAU's buildings, or else the map's extruded ones. */
function showPlateau(on) {
  if (on && !map.getLayer("plateau")) map.addLayer(layer);
  if (!on && map.getLayer("plateau")) map.removeLayer("plateau");
  map.setLayoutProperty("building-3d", "visibility", on ? "none" : "visible");
  feature.replaceChildren();
  showStatus();
}

const format = (v, unit = "") => (typeof v === "number" ? `${v.toLocaleString("ja-JP", { maximumFractionDigits: 1 })}${unit}` : String(v));

function row(label, value) {
  const tr = document.createElement("tr");
  const th = document.createElement("th");
  const td = document.createElement("td");
  th.textContent = label;
  td.textContent = value;
  tr.append(th, td);
  return tr;
}

/** The building's attributes: the usual ones, its flood ranks, then every attribute it has. */
function showFeature(hit) {
  feature.replaceChildren();
  if (!hit) return;
  const p = hit.properties;
  const given = (v) => v !== null && v !== undefined && v !== "" && typeof v !== "object";
  const table = document.createElement("table");
  for (const [key, label, unit] of SHOWN) if (given(p[key])) table.append(row(label, format(p[key], unit)));
  for (const [key, v] of Object.entries(p)) {
    if (!key.endsWith("_浸水ランク") || !given(v)) continue;
    // "<river>（<section>）_<scale>（<case>）_浸水ランク": the river and L1 / L2.
    const scale = key.match(/_(L\d)/)?.[1];
    table.append(row(`浸水ランク（${key.split(/[（_]/)[0]}${scale ? ` ${scale}` : ""}）`, format(v)));
  }
  const all = document.createElement("details");
  const summary = document.createElement("summary");
  summary.textContent = "すべての属性";
  const rest = document.createElement("table");
  for (const [key, v] of Object.entries(p)) if (given(v)) rest.append(row(key, String(v)));
  all.append(summary, rest);
  feature.append(table, all);
}

map.once("load").then(() => {
  showPlateau(true);
  map.on("render", showStatus);
  map.on("click", async (e) => showFeature(map.getLayer("plateau") ? await layer.queryFeature(e.point) : null));
  window.__loaded = performance.now();
});

document.getElementById("plateau").addEventListener("change", (e) => showPlateau(e.target.checked));
const places = document.getElementById("places");
for (const [name, camera] of PLACES) {
  const b = document.createElement("button");
  b.textContent = name;
  b.addEventListener("click", () => map.flyTo({ ...camera, duration: 1500 }));
  places.append(b);
}

const credit = document.getElementById("credit");
const link = document.createElement("a");
link.href = "https://www.mlit.go.jp/plateau/";
link.textContent = "https://www.mlit.go.jp/plateau/";
credit.append(
  `国土地理院ベクトルタイル提供実験 | 出典：「3D都市モデル（Project PLATEAU）千代田区（2025年度）」（国土交通省）（`,
  link,
  local ? "）を加工して作成（東京駅周辺のタイルを抜き出したもの）" : "）",
);
