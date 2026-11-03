// The showcase's map controls from `mbmap/ui` (drawn differently by each
// example): a scale and the attributions, zoom through the navigation, and the
// location from the fake Geolocation followed by the camera, its dot drawn.
export async function controlChecks(page) {
  const r = await page.evaluate(async () => {
    const c = window.__controls;
    const map = window.__map;
    const moved = () => map.once("moveend");
    const zoom = map.getZoom();
    let end = moved();
    c.nav.zoomIn();
    await end;
    const zoomedIn = map.getZoom();
    end = moved();
    c.nav.zoomOut();
    await end;
    c.geo.trigger();
    end = moved();
    window.__geo.push(139.7, 35.66, 80);
    await end;
    const center = map.getCenter();
    const located = await new Promise((resolve) => setTimeout(() => resolve(document.querySelector(".location:not([hidden]), .react-location") !== null), 100));
    return {
      scale: c.scale.state.label,
      credits: c.attribution.state.text,
      zoom,
      zoomedIn,
      status: c.geo.state.status,
      center: [center.lng, center.lat],
      radius: c.geo.state.accuracyRadius,
      located,
      buttons: document.querySelectorAll(".controls button, .toolbar button").length,
    };
  });
  const ok =
    /^\d+(\.\d+)?\u00a0(m|km)$/.test(r.scale) && r.credits.includes("国土地理院") &&
    Math.abs(r.zoomedIn - r.zoom - 1) < 1e-9 &&
    r.status === "active" && Math.abs(r.center[0] - 139.7) < 1e-6 && Math.abs(r.center[1] - 35.66) < 1e-6 && r.radius > 0 && r.located &&
    r.buttons >= 6;
  return { ok, ...r };
}
