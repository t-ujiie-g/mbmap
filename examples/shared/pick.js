// What the panel shows of a clicked feature (its layer, then its name, GSI's
// `knj` or the places' `name`, or its first properties), and the places'
// hover highlight.

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
