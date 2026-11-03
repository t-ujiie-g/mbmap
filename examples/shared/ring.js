// A custom layer (MapLibre's CustomLayerInterface): the analysis radius around Tokyo Station drawn
// with WebGL of its own, under the places. A new style drops custom layers, so it goes back each time.
import { RADIUS_METERS } from "./analysis.js";

const CENTER = [139.7671, 35.6812];
const SEGMENTS = 128;

/** The ring as a triangle strip in Mercator coordinates (0 to 1), its outer edge `RADIUS_METERS` out. */
function ringVertices() {
  const [lng, lat] = CENTER;
  const x = (180 + lng) / 360;
  const y = (180 - (180 / Math.PI) * Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360))) / 360;
  const r = RADIUS_METERS / (40075016.686 * Math.cos((lat * Math.PI) / 180));
  const out = [];
  for (let i = 0; i <= SEGMENTS; i++) {
    const a = (i / SEGMENTS) * 2 * Math.PI;
    for (const [k, edge] of [[0.94, 0], [1, 1]]) out.push(x + Math.cos(a) * r * k, y + Math.sin(a) * r * k, edge);
  }
  return new Float32Array(out);
}

function ringLayer() {
  return {
    id: "radius-ring",
    type: "custom",
    onAdd(map, gl) {
      const shader = (type, source) => {
        const s = gl.createShader(type);
        gl.shaderSource(s, `#version 300 es\nprecision highp float;\n${source}`);
        gl.compileShader(s);
        return s;
      };
      this.program = gl.createProgram();
      gl.attachShader(this.program, shader(gl.VERTEX_SHADER, "uniform mat4 u_matrix; in vec3 a_pos; out float v_edge; void main() { v_edge = a_pos.z; gl_Position = u_matrix * vec4(a_pos.xy, 0.0, 1.0); }"));
      // Premultiplied, as the map blends: a band fading out inward.
      gl.attachShader(this.program, shader(gl.FRAGMENT_SHADER, "in float v_edge; out vec4 o; void main() { float a = 0.55 * v_edge * v_edge; o = vec4(0.13, 0.4, 0.67, 1.0) * a; }"));
      gl.bindAttribLocation(this.program, 0, "a_pos");
      gl.linkProgram(this.program);
      this.matrix = gl.getUniformLocation(this.program, "u_matrix");
      this.buffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
      gl.bufferData(gl.ARRAY_BUFFER, ringVertices(), gl.STATIC_DRAW);
    },
    onRemove(map, gl) {
      gl.deleteProgram(this.program);
      gl.deleteBuffer(this.buffer);
    },
    render(gl, options) {
      gl.useProgram(this.program);
      gl.uniformMatrix4fv(this.matrix, false, options.defaultProjectionData.mainMatrix);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, (SEGMENTS + 1) * 2);
    },
  };
}

/** Keeps the ring on `map`, under the places, across style changes. */
export function keepRadiusRing(map) {
  const add = () => {
    if (map.getStyle() && !map.getLayer("radius-ring")) map.addLayer(ringLayer(), map.getLayer("places") ? "places" : undefined);
  };
  map.on("styledata", add);
  add();
}
