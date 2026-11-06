// The showcases' measuring and drawing tools (mbmap/geodesic, mbmap/draw and the
// controllers over them), checked alike in all three examples by npm/pack-test.mjs.
import path from "node:path";
import { ROOT } from "../../lib/root.mjs";
import { awaitAfter, openTab } from "./step.mjs";

// The showcase's measurement: a line ended by a double click (no zoom, no identify) and an area
// finished from the panel reach geographiclib-geodesic's numbers to the bit; 「消す」 empties the overlay.
export async function measureChecks(page) {
  // geographiclib in the page itself: engines' Math differ in the last bit now and then.
  await page.addScriptTag({ path: path.join(ROOT, "bench/node_modules/geographiclib-geodesic/geographiclib-geodesic.min.js") });
  // The numbers of the vertices placed, once the controller has them (vertices come at once, numbers from the worker).
  const measured = async (n, closed) => {
    await page.waitForFunction((n) => window.__measurement.state.positions.length === n && window.__measurement.state.finished, n);
    await page.waitForFunction((closed) => {
      const s = window.__measurement.state;
      const p = geodesic.Geodesic.WGS84.Polygon(!closed);
      for (const [lng, lat] of s.positions) p.AddPoint(lat, lng);
      const r = p.Compute(false, true);
      return s.length === r.perimeter && s.area === (closed ? Math.abs(r.area) : null) && s.segments.length === (closed ? s.positions.length : s.positions.length - 1);
    }, closed);
    return page.evaluate(() => window.__measurement.state);
  };
  const before = await page.evaluate(() => ({ zoom: window.__map.getZoom(), point: window.__identify.state.point }));
  await openTab(page, "measure");
  await page.click("#measure button >> text=距離");
  await page.mouse.click(420, 160);
  await page.mouse.click(620, 200);
  await page.mouse.move(560, 300, { steps: 2 });
  await page.mouse.dblclick(520, 380);
  const line = await measured(3, false);
  const after = await page.evaluate(() => ({ zoom: window.__map.getZoom(), point: window.__identify.state.point, layers: window.__map.getStyle().layers.filter((l) => l.id.startsWith("mbmap-measure")).map((l) => l.id) }));
  const text = await page.evaluate(() => document.getElementById("measured").textContent);
  const profiled = await profileChecks(page, line.length);
  await page.click("#measure button >> text=面積");
  for (const [x, y] of [[420, 160], [620, 200], [520, 380]]) await page.mouse.click(x, y);
  await page.click("#measure button >> text=終える");
  const area = await measured(3, true);
  await awaitAfter(page, "measure: 消す", () => page.click("#measure button >> text=消す"));
  const cleared = await page.evaluate(() => {
    return { mode: window.__measurement.state.mode, features: window.__map.getStyle().sources["mbmap-measure"].data.features.length, dblclick: window.__map.doubleClickZoom.isEnabled(), profile: window.__profile.state.distances.length };
  });
  const sum = (a) => a.reduce((x, y) => x + y, 0);
  const ok =
    line.mode === "distance" && line.segments.length === 2 && Math.abs(sum(line.segments) - line.length) < 1e-6 &&
    area.mode === "area" && area.segments.length === 3 && area.area > 0 &&
    after.zoom === before.zoom && JSON.stringify(after.point) === JSON.stringify(before.point) && after.layers.length === 3 && text.includes(" m") &&
    cleared.mode === null && cleared.features === 0 && cleared.dblclick && cleared.profile === 0 && profiled.ok;
  return { ok, profiled, line: { mode: line.mode, length: line.length, segments: line.segments }, area: { mode: area.mode, perimeter: area.length, area: area.area, segments: area.segments }, after, text, cleared };
}

// The profile of the measured line (mbmap/ui over mbmap/geodesic and mbmap/analysis's sampleDem):
// samples along it to its length, heights at each, and the chart's pointer shown as a dot on the map.
async function profileChecks(page, length) {
  await page.waitForFunction(() => !window.__profile.state.loading && window.__profile.state.distances.length > 2, null, { timeout: 30000 });
  const s = await page.evaluate(() => window.__profile.state);
  const box = await page.locator("#profile svg").boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForFunction(() => window.__profile.state.active >= 0);
  const pointed = await page.evaluate(() => {
    const p = window.__profile.state;
    const at = window.__map.project({ lng: p.path[p.active][0], lat: p.path[p.active][1] });
    const dot = document.querySelector(".profile-dot");
    return { active: p.active, hidden: dot.hidden, transform: dot.style.transform, want: `translate(${at.x}px, ${at.y}px)`, caption: document.getElementById("profile").textContent };
  });
  const ascending = s.distances.every((d, i) => i === 0 || d > s.distances[i - 1]);
  const ok =
    s.distances[0] === 0 && ascending && Math.abs(s.distances.at(-1) - length) < 1e-6 && Math.abs(s.length - length) < 1e-6 &&
    s.elevations.length === s.path.length && s.elevations.every(Number.isFinite) && s.min <= s.max && s.error === null &&
    !pointed.hidden && pointed.transform === pointed.want && pointed.caption.includes("登り");
  return { ok, samples: s.distances.length, min: s.min, max: s.max, gain: s.gain, pointed };
}

// The showcase's drawing (mbmap/draw): a polygon closed on its first vertex, a line finished with
// Enter, one cancelled with Escape, a circle by two clicks, undo and redo; measuring takes over.
export async function drawChecks(page) {
  await openTab(page, "draw");
  const state = () => page.evaluate(() => window.__draw.state);
  const clicks = async (points) => {
    for (const [x, y] of points) {
      await page.mouse.click(x, y);
      await page.waitForTimeout(350);
    }
  };
  const before = await page.evaluate(() => JSON.stringify(window.__identify.state.point));
  await page.click("#draw-modes button >> text=多角形");
  await clicks([[420, 160], [650, 200], [560, 420], [424, 163]]);
  const polygon = await state();
  await page.click("#draw-modes button >> text=線");
  await clicks([[450, 180], [620, 380]]);
  await page.keyboard.press("Enter");
  await clicks([[460, 200], [600, 300]]);
  await page.keyboard.press("Escape");
  const lines = await state();
  await page.click("#draw-modes button >> text=円");
  await clicks([[520, 300], [580, 300]]);
  await page.waitForFunction(() => window.__draw.state.features.length === 3);
  const circle = await state();
  await page.click("#draw-actions button >> text=一つ戻す");
  const undone = (await state()).features.length;
  await page.click("#draw-actions button >> text=やり直す");
  const redone = (await state()).features.length;
  const after = await page.evaluate(() => JSON.stringify(window.__identify.state.point));
  await openTab(page, "measure");
  await page.click("#measure button >> text=距離");
  const handed = await state();
  await page.click("#measure button >> text=消す");
  await openTab(page, "draw");
  await page.click("#draw-actions button >> text=全部消す");
  const end = await page.evaluate(() => ({ features: window.__draw.state.features.length, dblclick: window.__map.doubleClickZoom.isEnabled() }));
  const ring = polygon.features[0]?.geometry.coordinates[0] ?? [];
  let twice = 0;
  for (let i = 0; i + 1 < ring.length; i++) twice += ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1];
  const circleRing = circle.features[2]?.geometry.coordinates[0] ?? [];
  const ok =
    polygon.features.length === 1 && ring.length === 4 && twice > 0 && polygon.vertices.length === 0 &&
    lines.features.length === 2 && lines.features[1].geometry.type === "LineString" && lines.features[1].geometry.coordinates.length === 2 && lines.vertices.length === 0 &&
    circleRing.length === 65 && circle.features[2].properties.mode === "circle" &&
    undone === 2 && redone === 3 && before === after &&
    handed.mode === null && end.features === 0 && end.dblclick;
  return { ok, polygon: ring.length, lines: lines.features.length, circle: circleRing.length, undone, redone, handed: handed.mode, end };
}

// Editing with mbmap/draw's select mode: a vertex dragged (the map does not pan), a midpoint
// dragged into a vertex, one deleted by right click, the shape dragged whole, a vertex snapped
// onto another shape's, a name set from the panel and undone, the shape deleted with Delete.
export async function editChecks(page) {
  await openTab(page, "draw");
  const clicks = async (points) => {
    for (const [x, y] of points) {
      await page.mouse.click(x, y);
      await page.waitForTimeout(350);
    }
  };
  const drag = async ([x0, y0], [x1, y1]) => {
    await page.mouse.move(x0, y0);
    await page.mouse.down();
    await page.mouse.move(x1, y1, { steps: 6 });
    await page.mouse.up();
    await page.waitForTimeout(300);
  };
  const ring = () => page.evaluate(() => window.__draw.state.features[0]?.geometry.coordinates[0]);
  const at = (p) => page.evaluate(([lng, lat]) => window.__map.project({ lng, lat }), p);
  await page.click("#draw-modes button >> text=多角形");
  await clicks([[440, 180], [640, 180], [640, 380], [440, 380], [443, 183]]);
  await page.click("#draw-modes button >> text=選択");
  await clicks([[540, 280]]);
  const selected = await page.evaluate(() => window.__draw.state.selected);
  const center = await page.evaluate(() => window.__map.getCenter());
  // Drag the vertex nearest (640, 380) to (690, 420).
  const first = await ring();
  await drag([640, 380], [690, 420]);
  const moved = await ring();
  const still = await page.evaluate(() => window.__map.getCenter());
  // The midpoint of the first edge (the left side: the ring is counter-clockwise), dragged out into a fifth vertex.
  const [a, b] = [await at(moved[0]), await at(moved[1])];
  const mid = [(a.x + b.x) / 2, (a.y + b.y) / 2];
  await drag(mid, [mid[0] - 40, mid[1]]);
  const inserted = (await ring()).length;
  // Right click on that vertex deletes it.
  await page.mouse.click(mid[0] - 40, mid[1], { button: "right" });
  await page.waitForTimeout(300);
  const deleted = (await ring()).length;
  // The body dragged 30 px right moves every vertex.
  const before = await ring();
  await drag([520, 300], [550, 300]);
  const shifted = await ring();
  const allMoved = shifted.every((p, i) => p[0] > before[i][0] && Math.abs(p[1] - before[i][1]) < 1e-9);
  // A second shape whose first vertex is clicked 8 px from the first shape's: it snaps onto it.
  const corner = await at(shifted[0]);
  await page.click("#draw-modes button >> text=点");
  await clicks([[corner.x + 6, corner.y + 5]]);
  const snapped = await page.evaluate(() => window.__draw.state.features[1].geometry.coordinates);
  // Fields: a name set, then undone; Delete removes the selected shape.
  await page.click("#draw-modes button >> text=選択");
  await clicks([[560, 300]]);
  await page.fill("#draw-fields input[name=name]", "区画A");
  await page.press("#draw-fields input[name=name]", "Enter");
  await page.locator("#draw-fields input[name=name]").blur();
  await page.waitForTimeout(200);
  const named = await page.evaluate(() => window.__draw.state.features.find((f) => f.id === window.__draw.state.selected)?.properties.name);
  await page.click("#draw-actions button >> text=一つ戻す");
  const unnamed = await page.evaluate(() => window.__draw.state.features[0].properties.name ?? null);
  await clicks([[560, 300]]);
  await page.keyboard.press("Delete");
  const left = await page.evaluate(() => window.__draw.state.features.length);
  await page.evaluate(() => (window.__draw.clear(), window.__draw.setMode(null)));
  const pan = await page.evaluate(() => window.__map.dragPan.isEnabled());
  const changed = moved.filter((p, i) => p[0] !== first[i][0] || p[1] !== first[i][1]).length;
  const ok =
    selected !== null && changed === 1 && still.lng === center.lng && still.lat === center.lat &&
    inserted === 6 && deleted === 5 && allMoved &&
    JSON.stringify(snapped) === JSON.stringify(shifted[0]) &&
    named === "区画A" && unnamed === null && left === 1 && pan;
  return { ok, selected, changed, inserted, deleted, allMoved, snapped, corner: shifted[0], named, unnamed, left, pan };
}

// Split and merge (mbmap/draw over mbmap/analysis's geometry module): a rectangle cut in two by a
// line drawn across it, the halves selected with Shift and merged back, the merge undone.
export async function splitChecks(page) {
  await openTab(page, "draw");
  const clicks = async (points) => {
    for (const [x, y] of points) {
      await page.mouse.click(x, y);
      await page.waitForTimeout(350);
    }
  };
  const shapes = () => page.evaluate(() => window.__draw.state.features.map((f) => ({ type: f.geometry.type, ring: f.geometry.coordinates[0] })));
  // Twice the planar area in degrees of a closed ring (counter-clockwise positive).
  const area = (r) => r.slice(1).reduce((a, p, i) => a + r[i][0] * p[1] - p[0] * r[i][1], 0);
  await page.click("#draw-modes button >> text=矩形");
  await clicks([[440, 180], [660, 400]]);
  const whole = area((await shapes())[0].ring);
  await page.click("#draw-modes button >> text=分割");
  await clicks([[550, 140], [560, 450], [560, 450]]);
  await page.waitForFunction(() => window.__draw.state.features.length === 2, null, { timeout: 10000 });
  const halves = await shapes();
  await page.click("#draw-modes button >> text=選択");
  await clicks([[470, 290]]);
  await page.keyboard.down("Shift");
  await clicks([[630, 290]]);
  await page.keyboard.up("Shift");
  const picked = await page.evaluate(() => window.__draw.state.selection.length);
  await page.click("#draw-actions button >> text=結合");
  await page.waitForFunction(() => window.__draw.state.features.length === 1, null, { timeout: 10000 });
  const merged = await shapes();
  await page.click("#draw-actions button >> text=一つ戻す");
  const undone = (await shapes()).length;
  await page.evaluate(() => (window.__draw.clear(), window.__draw.setMode(null)));
  const zooms = await page.evaluate(() => [window.__map.boxZoom.isEnabled(), window.__map.doubleClickZoom.isEnabled()]);
  const sum = halves.reduce((a, h) => a + area(h.ring), 0);
  // The geometry module works on a 1e-7 degree grid, which moves the areas by a few millionths.
  const ok =
    halves.length === 2 && halves.every((h) => h.type === "Polygon" && area(h.ring) > 0) && Math.abs(sum - whole) / whole < 1e-4 &&
    picked === 2 && merged.length === 1 && merged[0].type === "Polygon" && Math.abs(area(merged[0].ring) - whole) / whole < 1e-4 &&
    undone === 2 && zooms.every(Boolean);
  return { ok, whole, halves: halves.map((h) => area(h.ring)), picked, merged: merged.map((m) => m.type), undone, zooms };
}
