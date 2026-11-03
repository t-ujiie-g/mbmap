// Image, video and canvas sources on bench/npm/pages/media: each shows where its corners put it; a playing canvas is drawn
// again each frame and kept when paused; the video pauses and plays; the image moves, takes a new picture, refuses a URL
// that is not http(s) and comes back with its layer; the map goes idle while the video plays and when the layer is shown.
import { near as within, pixel } from "./pixels.mjs";
import { step } from "./step.mjs";

const near = (rgb, want, d = 8) => within(rgb, want, d);
const white = [255, 255, 255];

export async function mediaChecks(page, requests) {
  const frames = (n) => page.evaluate((k) => new Promise((done) => {
    const step = (i) => (i === 0 ? done() : requestAnimationFrame(() => step(i - 1)));
    step(k);
  }), n);
  await page.waitForFunction(() => {
    const v = window.__map.getSource("clip").getVideo?.();
    return v && v.readyState >= 2 && !v.paused;
  }, null, { timeout: 30000 });
  await frames(3);
  const at = await page.evaluate(() => {
    const map = window.__map;
    const idle = Promise.race([map.once("idle").then(() => true), new Promise((r) => setTimeout(() => r(false), 5000))]);
    return Promise.all([idle, ...[-20, 0, 20].map((lng) => map.project([lng, 0]))]).then(([idle, ...p]) => ({ idle, p }));
  });
  const [picture, clip, paint] = at.p;
  const shown = { picture: await pixel(page, picture.x, picture.y), clip: await pixel(page, clip.x, clip.y), paint: await pixel(page, paint.x, paint.y) };

  // The canvas: drawn again while it plays, kept while paused.
  const fill = (color) => page.evaluate((c) => {
    window.__paint.fillStyle = c;
    window.__paint.fillRect(0, 0, 16, 16);
  }, color);
  await fill("#0000ff");
  await frames(3);
  const playing = await pixel(page, paint.x, paint.y);
  await page.evaluate(() => window.__map.getSource("paint").pause());
  await fill("#00ff00");
  await frames(3);
  const paused = await pixel(page, paint.x, paint.y);
  await page.evaluate(() => window.__map.getSource("paint").play());
  await frames(3);
  const resumed = await pixel(page, paint.x, paint.y);

  // The video pauses and plays.
  const video = await page.evaluate(async () => {
    const s = window.__map.getSource("clip");
    s.pause();
    const pausedNow = s.getVideo().paused;
    s.play();
    await new Promise((r) => s.getVideo().addEventListener("playing", r, { once: true }));
    return { paused: pausedNow, playing: !s.getVideo().paused, canvas: window.__map.getSource("paint").getCanvas()?.id };
  });

  // The image moves north, takes the canvas as its picture, and refuses a data: URL.
  const moved = await page.evaluate(async () => {
    const map = window.__map;
    const s = map.getSource("picture");
    const errors = [];
    map.on("error", (e) => errors.push(e.error.message));
    s.setCoordinates([[-30, 24], [-10, 24], [-10, 12], [-30, 12]]);
    await map.once("idle");
    const north = map.project([-20, 18]);
    s.updateImage({ image: document.getElementById("paint") });
    s.updateImage({ url: "data:image/png;base64,AAAA" });
    await map.once("idle");
    return { north, errors, coordinates: map.getStyle().sources.picture.coordinates[0] };
  });
  await frames(3);
  const left = await pixel(page, picture.x, picture.y);
  const north = await pixel(page, moved.north.x, moved.north.y);
  await step(page, "media: hide the image", `map.setLayoutProperty("picture", "visibility", "none");`);
  const hidden = await pixel(page, moved.north.x, moved.north.y);
  const reshown = await step(page, "media: show the image again", `map.setLayoutProperty("picture", "visibility", "visible");`, { timeout: 10_000 })
    .then(() => true, (e) => e.message);
  const back = await pixel(page, moved.north.x, moved.north.y);

  const loaded = requests.map((u) => u.split("/").pop());
  const r = { idle: at.idle, shown, playing, paused, resumed, video, moved, left, north, hidden, reshown, back, loaded: loaded.filter((n) => /media|clip|sketch/.test(n)) };
  const ok =
    at.idle &&
    !near(shown.picture, white, 30) &&
    (near(shown.clip, [255, 0, 0], 60) || near(shown.clip, [0, 0, 255], 60)) &&
    near(shown.paint, [255, 0, 0]) && near(playing, [0, 0, 255]) && near(paused, [0, 0, 255]) && near(resumed, [0, 255, 0]) &&
    video.paused && video.playing && video.canvas === "paint" &&
    near(left, white) && near(north, [0, 255, 0]) && near(hidden, white) && reshown === true && near(back, [0, 255, 0]) &&
    JSON.stringify(moved.coordinates) === "[-30,24]" && moved.errors.some((e) => /http\(s\)/.test(e)) &&
    ["media.js", "clip.webm", "station-sketch.png"].every((n) => loaded.includes(n));
  return [ok, r];
}
