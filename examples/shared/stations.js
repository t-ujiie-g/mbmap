// The Yamanote Line's stations as a clustered GeoJSON source (positions rounded
// to about 10 m): circles sized by the number of stations in each cluster, its
// count as a label, and a click on a cluster zooming to where it breaks apart.

const POINTS = [
  ["東京", 139.7671, 35.6812], ["有楽町", 139.7631, 35.6751], ["新橋", 139.7583, 35.6663],
  ["浜松町", 139.757, 35.6555], ["田町", 139.7476, 35.6457], ["高輪ゲートウェイ", 139.7405, 35.6355],
  ["品川", 139.7387, 35.6285], ["大崎", 139.7284, 35.6197], ["五反田", 139.7236, 35.6262],
  ["目黒", 139.7157, 35.6339], ["恵比寿", 139.7101, 35.6467], ["渋谷", 139.7016, 35.658],
  ["原宿", 139.7027, 35.6702], ["代々木", 139.702, 35.6831], ["新宿", 139.7006, 35.6896],
  ["新大久保", 139.7003, 35.7012], ["高田馬場", 139.7038, 35.7126], ["目白", 139.7066, 35.7212],
  ["池袋", 139.7109, 35.7295], ["大塚", 139.7286, 35.7317], ["巣鴨", 139.7393, 35.7334],
  ["駒込", 139.7468, 35.7365], ["田端", 139.7608, 35.7381], ["西日暮里", 139.7668, 35.732],
  ["日暮里", 139.771, 35.7278], ["鶯谷", 139.7781, 35.7214], ["上野", 139.7774, 35.7141],
  ["御徒町", 139.7748, 35.7074], ["秋葉原", 139.7731, 35.6984], ["神田", 139.7708, 35.6918],
];

export const STATIONS = {
  type: "FeatureCollection",
  features: POINTS.map(([name, lng, lat]) => ({ type: "Feature", properties: { name }, geometry: { type: "Point", coordinates: [lng, lat] } })),
};

/** The source: clusters of 50 px up to zoom 14. */
export const STATIONS_SOURCE = { type: "geojson", data: STATIONS, cluster: true, clusterRadius: 50, clusterMaxZoom: 14 };

/** The layers (overlays, kept across basemaps): clusters, their counts, and single stations. */
export function stationLayers(metadata) {
  const clustered = ["has", "point_count"];
  return [
    {
      id: "stations-cluster", type: "circle", source: "stations", filter: clustered, metadata,
      paint: {
        "circle-color": "#5a9e3a",
        "circle-opacity": 0.85,
        "circle-radius": ["step", ["get", "point_count"], 12, 5, 16, 10, 22],
        "circle-stroke-width": 2,
        "circle-stroke-color": "#ffffff",
      },
    },
    {
      id: "stations", type: "circle", source: "stations", filter: ["!", clustered], metadata,
      paint: { "circle-color": "#5a9e3a", "circle-radius": 4, "circle-stroke-width": 1, "circle-stroke-color": "#ffffff" },
    },
    {
      id: "stations-count", type: "symbol", source: "stations", filter: clustered, metadata,
      layout: { "text-field": "{point_count_abbreviated}", "text-size": 12, "text-allow-overlap": true },
      paint: { "text-color": "#ffffff" },
    },
  ];
}

/** A click on a cluster eases the map to the zoom at which it breaks apart, centered on it. */
export function zoomIntoClusters(map) {
  map.on("click", "stations-cluster", async (e) => {
    const f = e.features[0];
    const zoom = await map.getSource("stations").getClusterExpansionZoom(f.properties.cluster_id);
    map.easeTo({ center: f.geometry.coordinates, zoom });
    window.__clusterZoom = zoom;
  });
}
