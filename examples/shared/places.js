// Places the showcase flies to, and major stations and landmarks as a
// GeoJSON layer (positions rounded to about 10 m; `kind` 駅, 名所 or 山).

/** Buttons: where each goes (with `?local=1`, only Tokyo Station has tiles). */
export const DESTINATIONS = [
  { name: "東京駅", center: [139.7671, 35.6812], zoom: 15 },
  { name: "富士山", center: [138.7274, 35.3606], zoom: 11.5 },
  { name: "大阪駅", center: [135.4959, 34.7025], zoom: 15 },
  { name: "京都", center: [135.7588, 34.9858], zoom: 14 },
  { name: "札幌駅", center: [141.3508, 43.0686], zoom: 15 },
];

const POINTS = [
  ["東京駅", 139.7671, 35.6812],
  ["有楽町駅", 139.7631, 35.6751],
  ["神田駅", 139.7708, 35.6918],
  ["日本橋", 139.7745, 35.6840],
  ["皇居", 139.7528, 35.6852],
  ["新宿駅", 139.7006, 35.6896],
  ["渋谷駅", 139.7016, 35.6580],
  ["池袋駅", 139.7109, 35.7295],
  ["上野駅", 139.7774, 35.7141],
  ["品川駅", 139.7387, 35.6285],
  ["東京タワー", 139.7454, 35.6586],
  ["東京スカイツリー", 139.8107, 35.7101],
  ["富士山", 138.7274, 35.3606],
  ["大阪駅", 135.4959, 34.7025],
  ["大阪城", 135.5262, 34.6873],
  ["京都駅", 135.7588, 34.9858],
  ["名古屋駅", 136.8815, 35.1709],
  ["札幌駅", 141.3508, 43.0686],
  ["仙台駅", 140.8824, 38.2601],
  ["広島駅", 132.4757, 34.3976],
  ["博多駅", 130.4207, 33.5897],
];

const kindOf = (name) => (name.endsWith("駅") ? "駅" : name === "富士山" ? "山" : "名所");

export const PLACES = {
  type: "FeatureCollection",
  features: POINTS.map(([name, lng, lat]) => ({ type: "Feature", properties: { name, kind: kindOf(name) }, geometry: { type: "Point", coordinates: [lng, lat] } })),
};
