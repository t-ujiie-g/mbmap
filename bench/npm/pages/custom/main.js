// A custom layer under a GeoJSON square, for the pack test's custom layer check
// (bench/npm/checks/custom.mjs): it draws a blue box through MapLibre's shader prelude
// and leaves the GL state in a mess, which the map must undo.
import { Map } from "mbmap";

const map = new Map({
  container: "map",
  center: [0, 0],
  zoom: 3,
  style: {
    version: 8,
    sources: {
      square: {
        type: "geojson",
        data: { type: "Feature", properties: {}, geometry: { type: "Polygon", coordinates: [[[5, -5], [15, -5], [15, 5], [5, 5], [5, -5]]] } },
      },
    },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#ffffff" } },
      { id: "square", type: "fill", source: "square", paint: { "fill-color": "#ff0000", "fill-antialias": false } },
    ],
  },
});

const mercator = ([lng, lat]) => [(180 + lng) / 360, (180 - (180 / Math.PI) * Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360))) / 360];
const box = {
  id: "box",
  type: "custom",
  renderingMode: "2d",
  calls: { added: 0, removed: 0, prerender: 0, render: 0 },
  onAdd(m, gl) {
    this.calls.added++;
    this.gotMap = m === map;
    this.buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([[-10, -6], [10, -6], [-10, 6], [10, 6]].flatMap(mercator)), gl.STATIC_DRAW);
  },
  onRemove() {
    this.calls.removed++;
  },
  prerender() {
    this.calls.prerender++;
  },
  render(gl, options) {
    this.calls.render++;
    this.options = options;
    this.depth = gl.isEnabled(gl.DEPTH_TEST);
    if (!this.program) {
      const shader = (type, source) => {
        const s = gl.createShader(type);
        gl.shaderSource(s, source);
        gl.compileShader(s);
        if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
        return s;
      };
      const { vertexShaderPrelude, define } = options.shaderData;
      this.program = gl.createProgram();
      gl.attachShader(this.program, shader(gl.VERTEX_SHADER, `#version 300 es\n${vertexShaderPrelude}\n${define}\nin vec2 a_pos;\nvoid main() { gl_Position = projectTile(a_pos); }`));
      gl.attachShader(this.program, shader(gl.FRAGMENT_SHADER, "#version 300 es\nprecision highp float;\nout vec4 o;\nvoid main() { o = vec4(0.0, 0.0, 1.0, 1.0); }"));
      gl.bindAttribLocation(this.program, 0, "a_pos");
      gl.linkProgram(this.program);
    }
    gl.useProgram(this.program);
    gl.uniformMatrix4fv(gl.getUniformLocation(this.program, "u_projection_matrix"), false, options.defaultProjectionData.mainMatrix);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    // State the map relies on, left broken.
    gl.enable(gl.CULL_FACE);
    gl.cullFace(gl.FRONT_AND_BACK);
    gl.blendFunc(gl.ZERO, gl.ZERO);
    gl.enable(gl.SCISSOR_TEST);
    gl.scissor(0, 0, 1, 1);
    gl.colorMask(false, false, false, false);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
    gl.activeTexture(gl.TEXTURE3);
  },
};

map.on("error", (e) => console.error(e.error));
map.once("load").then(() => {
  map.addLayer(box, "square");
  window.__loaded = performance.now();
});
window.__map = map;
window.__box = box;
