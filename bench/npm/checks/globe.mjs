// The globe on bench/npm/pages/globe: space around it stays clear, the camera projects onto the sphere,
// a custom layer gets MapLibre's globe options and draws through its globe prelude, a drag turns it and the wheel zooms, a flight ends in mercator at the target, and setProjection(null)
// flattens the map.
import { near, pixel } from "./pixels.mjs";

const white = [255, 255, 255];

export async function globeChecks(page) {
  await page.evaluate(() => window.__settled());
  const space = await pixel(page, 5, 5);
  const middle = await pixel(page, 400, 300);
  const r1 = await page.evaluate(() => {
    const map = window.__map;
    const c = map.project([139.7, 35.7]);
    const back = map.unproject([400, 300]);
    const far = map.unproject([5, 5]);
    return { projection: map.getProjection(), c: [c.x, c.y], back: [back.lng, back.lat], far: [far.lng, far.lat], bounds: map.getBounds().toArray() };
  });
  const custom = await page.evaluate(async () => {
    const map = window.__map;
    const t = ([lng, lat]) => [(180 + lng) / 360, (180 - (180 / Math.PI) * Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360))) / 360];
    const layer = {
      id: "quad",
      type: "custom",
      render(gl, o) {
        this.options = o;
        const d = o.defaultProjectionData;
        if (!this.program) {
          const shader = (type, source) => {
            const s = gl.createShader(type);
            gl.shaderSource(s, source);
            gl.compileShader(s);
            if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
            return s;
          };
          const p = gl.createProgram();
          gl.attachShader(p, shader(gl.VERTEX_SHADER, `#version 300 es\n${o.shaderData.define}\n${o.shaderData.vertexShaderPrelude}\nin vec2 a_pos;\nvoid main() { gl_Position = projectTile(a_pos); }`));
          gl.attachShader(p, shader(gl.FRAGMENT_SHADER, "#version 300 es\nprecision highp float;\nin highp float v_projection_tile_x;\nout vec4 o;\nvoid main() { o = vec4(1.0, 0.0, 1.0, 1.0); }"));
          gl.bindAttribLocation(p, 0, "a_pos");
          gl.linkProgram(p);
          this.program = p;
          this.buffer = gl.createBuffer();
          gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
          gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([[130, 30], [150, 30], [130, 42], [150, 42]].flatMap(t)), gl.STATIC_DRAW);
        }
        const p = this.program;
        const u = (n) => gl.getUniformLocation(p, n);
        gl.useProgram(p);
        gl.uniformMatrix4fv(u("u_projection_matrix"), false, d.mainMatrix);
        gl.uniformMatrix4fv(u("u_projection_fallback_matrix"), false, d.fallbackMatrix);
        gl.uniform4fv(u("u_projection_tile_mercator_coords"), d.tileMercatorCoords);
        gl.uniform4fv(u("u_projection_clipping_plane"), d.clippingPlane);
        gl.uniform1f(u("u_projection_transition"), d.projectionTransition);
        gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      },
    };
    map.addLayer(layer);
    await window.__settled();
    const o = layer.options;
    return {
      variant: o?.shaderData.variantName, define: o?.shaderData.define, f32: o?.defaultProjectionData.mainMatrix instanceof Float32Array,
      transition: o?.defaultProjectionData.projectionTransition, plane: o?.defaultProjectionData.clippingPlane.some((v) => v !== 0),
    };
  });
  const quad = await pixel(page, 400, 300);
  const left = await pixel(page, 5, 300);
  await page.evaluate(async () => {
    window.__map.removeLayer("quad");
    await window.__settled();
  });
  await page.mouse.move(400, 300);
  await page.mouse.down();
  await page.mouse.move(350, 300, { steps: 5 });
  await page.mouse.up();
  const dragged = await page.evaluate(() => window.__map.getCenter().lng);
  await page.mouse.wheel(0, -200);
  await page.waitForTimeout(400);
  const zoomed = await page.evaluate(() => window.__map.getZoom());
  const flown = await page.evaluate(async () => {
    const map = window.__map;
    const ended = map.once("moveend");
    map.flyTo({ center: [2.35, 48.85], zoom: 13, duration: 600 });
    await ended;
    await window.__settled();
    const c = map.getCenter();
    return [c.lng, c.lat, map.getZoom()];
  });
  const flatCorner = await pixel(page, 5, 5);
  const flat = await page.evaluate(async () => {
    const map = window.__map;
    map.jumpTo({ center: [139.7, 35.7], zoom: 1 });
    map.setProjection(null);
    await window.__settled();
    return { projection: map.getProjection(), zoom: map.getZoom() };
  });
  const flatSpace = await pixel(page, 5, 5);
  const ok =
    near(space, white) && !near(middle, white) &&
    r1.projection?.type === "globe" &&
    Math.abs(r1.c[0] - 400) < 1e-6 && Math.abs(r1.c[1] - 300) < 1e-6 &&
    Math.abs(r1.back[0] - 139.7) < 1e-6 && Math.abs(r1.back[1] - 35.7) < 1e-6 &&
    r1.bounds[0][0] < 139.7 && r1.bounds[1][0] > 139.7 &&
    custom.variant === "globe" && custom.define === "#define GLOBE" && custom.f32 && custom.transition === 1 && custom.plane &&
    near(quad, [255, 0, 255]) && near(left, white) &&
    dragged > 139.7 + 1 && zoomed > 1 &&
    Math.abs(flown[0] - 2.35) < 1e-6 && Math.abs(flown[1] - 48.85) < 1e-6 && flown[2] === 13 && !near(flatCorner, white) &&
    flat.projection === null && flat.zoom === 1 && !near(flatSpace, white);
  return ["globe", ok, { space, middle, ...r1, custom, quad, left, dragged, zoomed, flown, flatCorner, flat, flatSpace }];
}
