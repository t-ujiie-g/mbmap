// The contents of a 3D Tiles 1.0 tileset to keep for views of a box: every tile whose `region`
// meets `box` ([west, south, east, north] in degrees) and every ancestor of one.
export function tilesetSubset(tileset, box) {
  const [w, s, e, n] = box.map((d) => (d * Math.PI) / 180);
  const meets = (r) => r[0] <= e && r[2] >= w && r[1] <= n && r[3] >= s;
  const kept = new Set();
  const walk = (tile, chain) => {
    const region = tile.boundingVolume?.region;
    if (!region) throw new Error("tileset: a tile without a region bounding volume");
    const uri = tile.content?.uri ?? tile.content?.url;
    if (uri !== undefined) chain = [...chain, contentPath(uri)];
    if (meets(region)) for (const u of chain) kept.add(u);
    for (const child of tile.children ?? []) walk(child, chain);
  };
  walk(tileset.root, []);
  return [...kept].sort();
}

// Content URIs come from the network: only relative paths that stay under the tileset's directory.
function contentPath(uri) {
  if (typeof uri !== "string" || !/^[\w.-]+(\/[\w.-]+)*$/.test(uri) || uri.split("/").some((p) => p === ".." || p === "."))
    throw new Error(`tileset: content uri ${JSON.stringify(uri)} is not a plain relative path`);
  if (uri.endsWith(".json")) throw new Error(`tileset: external tileset ${uri} is not supported`);
  return uri;
}
