// Steps of the pack-test checks that wait for a map event: the listener goes in before the step acts, and a
// step whose event does not come fails after `timeout` ms with its label. `trail` keeps the labels entered last.
export const trail = [];

/** Records that the check entered step `label`. */
export function crumb(label) {
  trail.push(label);
  if (trail.length > 10) trail.shift();
}

/**
 * Runs `body` (a function body over `map`; it may await and return a value) on `window.__map`, then waits
 * for the map's `event`.
 */
export async function step(page, label, body, { event = "idle", timeout = 30_000 } = {}) {
  crumb(label);
  return page.evaluate(async ([b, event, timeout, label]) => {
    const map = window.__map;
    let timer;
    const done = new Promise((resolve, reject) => {
      map.once(event).then(resolve);
      timer = setTimeout(() => reject(new Error(`${label}: no ${event} after ${timeout} ms`)), timeout);
    });
    try {
      const out = await new Function("map", `return (async () => { ${b} })()`)(map);
      await done;
      return out;
    } finally {
      clearTimeout(timer);
    }
  }, [body, event, timeout, label]);
}

/** Like `step`, for an `action` done from outside the page (a click, a key press). */
export async function awaitAfter(page, label, action, { event = "idle", timeout = 30_000 } = {}) {
  crumb(label);
  await page.evaluate((event) => {
    window.__awaited = window.__map.once(event);
  }, event);
  await action();
  await page.evaluate(([event, timeout, label]) => {
    let timer;
    const late = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`${label}: no ${event} after ${timeout} ms`)), timeout);
    });
    return Promise.race([window.__awaited, late]).then(() => clearTimeout(timer), (e) => { clearTimeout(timer); throw e; });
  }, [event, timeout, label]);
}

/** What the page's map says it is doing (moving, loaded), or why it did not answer within 5 s. */
export async function mapState(page) {
  const state = page.evaluate(() => {
    const map = window.__map;
    return map ? { moving: map.isMoving(), loaded: map.loaded() } : "no map";
  });
  const late = new Promise((resolve) => setTimeout(() => resolve("no answer after 5 s"), 5000));
  return Promise.race([state.catch((e) => `failed: ${e.message}`), late]);
}
