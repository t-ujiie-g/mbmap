// The showcases' clustered stations, alike in all three examples: the clusters drawn at zoom 11 hold
// all 30, the source's cluster queries agree with them and refuse bad arguments, and a click on a
// cluster eases the map to its expansion zoom.
export async function clusterChecks(page) {
  const r = await page.evaluate(async () => {
    const map = window.__map;
    map.jumpTo({ center: [139.738, 35.681], zoom: 11, pitch: 0, bearing: 0 });
    await map.once("idle");
    const rendered = await map.queryRenderedFeatures({ layers: ["stations-cluster", "stations"] });
    const clusters = new Map();
    const singles = new Set();
    for (const f of rendered) {
      if (f.properties.cluster) clusters.set(f.properties.cluster_id, f);
      else singles.add(f.properties.name);
    }
    const counts = [...clusters.values()].map((f) => f.properties.point_count);
    const big = [...clusters.values()].sort((a, b) => b.properties.point_count - a.properties.point_count)[0];
    const source = map.getSource("stations");
    const id = big.properties.cluster_id;
    const children = await source.getClusterChildren(id);
    const leaves = await source.getClusterLeaves(id, Infinity);
    const paged = await source.getClusterLeaves(id, 2, 1);
    const refused = (p) => p.then(() => "", (e) => e.message);
    const rect = map.getContainer().getBoundingClientRect();
    const at = map.project(big.geometry.coordinates);
    return {
      counts,
      singles: singles.size,
      count: big.properties.point_count,
      abbreviated: big.properties.point_count_abbreviated,
      zoom: await source.getClusterExpansionZoom(id),
      children: children.map((c) => c.properties.point_count ?? 1),
      leaves: leaves.map((l) => l.properties.name),
      paged: paged.map((l) => l.properties.name),
      unknown: await refused(source.getClusterChildren(-5)),
      badLimit: await refused(source.getClusterLeaves(id, -1)),
      badId: await refused(source.getClusterExpansionZoom(1.5)),
      unclustered: await map.getSource("places").getClusterExpansionZoom(1),
      click: { x: rect.left + at.x, y: rect.top + at.y },
    };
  });
  await page.mouse.click(r.click.x, r.click.y);
  await page.waitForFunction(() => window.__clusterZoom !== undefined && !window.__map.isMoving(), null, { timeout: 30000 });
  const zoomed = await page.evaluate(() => ({ asked: window.__clusterZoom, zoom: window.__map.getZoom() }));
  const sum = (a) => a.reduce((x, y) => x + y, 0);
  const ok =
    r.counts.length > 0 && sum(r.counts) + r.singles === 30 &&
    r.abbreviated === r.count && r.zoom > 11 && r.zoom <= 15 &&
    sum(r.children) === r.count && r.leaves.length === r.count && new Set(r.leaves).size === r.count &&
    JSON.stringify(r.paged) === JSON.stringify(r.leaves.slice(1, 3)) &&
    /No cluster with the specified id: -5/.test(r.unknown) && /bad limit/.test(r.badLimit) && /no cluster with the id 1.5/.test(r.badId) &&
    r.unclustered === null &&
    zoomed.asked === r.zoom && zoomed.zoom === r.zoom;
  return { ok, ...r, zoomed };
}
