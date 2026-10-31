// Loads the bench tile fixtures; `fetchBytes(relPath)` reads a repo-relative
// file (fs in Node, fetch in a Worker) and returns a Uint8Array.
export async function loadFixtures(fetchBytes) {
  const manifest = JSON.parse(new TextDecoder().decode(await fetchBytes("bench/fixtures/gsi-bvmap.manifest.json")));
  const tiles = [];
  for (const key of Object.keys(manifest.tiles)) {
    tiles.push({ key, buf: await fetchBytes(`bench/fixtures/gsi-bvmap/${key}.pbf`) });
  }
  return tiles;
}

export const CENTER_TILE = "14/14552/6451";

export const workerFetchBytes = async (rel) => new Uint8Array(await (await fetch(`/${rel}`)).arrayBuffer());
