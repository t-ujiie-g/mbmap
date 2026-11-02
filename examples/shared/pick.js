// What the panel shows of a clicked feature: its layer, then its name (GSI's
// `knj`, the places' `name`) or its first properties.

/** Rows of [label, value] for the topmost of `features`, or null when there is none. */
export function describeFeature(features) {
  const f = features[0];
  if (!f) return null;
  const p = f.properties;
  const name = p.name ?? p.knj;
  const rest = Object.entries(p).filter(([k]) => k !== "name" && k !== "knj").slice(0, name === undefined ? 4 : 2);
  return [["レイヤー", f.layer.id], ...(name === undefined ? [] : [["名前", String(name)]]), ...rest.map(([k, v]) => [k, String(v)])];
}
