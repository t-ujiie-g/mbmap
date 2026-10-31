///|
/// An HTMLCanvasElement (or OffscreenCanvas).
#external
pub type Canvas

///|
/// A JS ArrayBuffer holding packed vertices or indices from the worker.
#external
pub type JsBuffer

///|
/// GPU buffers and vertex array of one tile layer.
#external
pub type Mesh

///|
#external
type Gl

///|
/// The WebGL2 context with its two programs; JS null if WebGL2 is unavailable.
extern "js" fn create_gl(canvas : Canvas) -> Gl =
  #|(canvas) => {
  #|  const gl = canvas.getContext("webgl2", { antialias: false, alpha: false, depth: false, stencil: false, premultipliedAlpha: true });
  #|  if (!gl) return null;
  #|  const compile = (type, src) => {
  #|    const s = gl.createShader(type);
  #|    gl.shaderSource(s, src);
  #|    gl.compileShader(s);
  #|    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
  #|    return s;
  #|  };
  #|  const program = (vs, fs, uniforms) => {
  #|    const p = gl.createProgram();
  #|    gl.attachShader(p, compile(gl.VERTEX_SHADER, "#version 300 es\n" + vs));
  #|    gl.attachShader(p, compile(gl.FRAGMENT_SHADER, "#version 300 es\nprecision highp float;\n" + fs));
  #|    gl.bindAttribLocation(p, 0, "a_pos");
  #|    gl.bindAttribLocation(p, 1, "a_data");
  #|    gl.linkProgram(p);
  #|    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
  #|    const u = { program: p };
  #|    for (const name of uniforms) u[name] = gl.getUniformLocation(p, name);
  #|    return u;
  #|  };
  #|  // u_clip is a rectangle in tile units outside which nothing is drawn: a
  #|  // loaded ancestor stands in for a missing tile clipped to its area.
  #|  const clip = "uniform vec4 u_clip; in vec2 v_pos;" +
  #|    "bool outside() { return any(lessThan(v_pos, u_clip.xy)) || any(greaterThanEqual(v_pos, u_clip.zw)); }";
  #|  const fill = program(
  #|    "in vec2 a_pos; uniform mat4 u_matrix; out vec2 v_pos;" +
  #|    "void main() { v_pos = a_pos; gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); }",
  #|    clip + "uniform vec4 u_color; out vec4 o; void main() { if (outside()) discard; o = u_color; }",
  #|    ["u_matrix", "u_clip", "u_color"]);
  #|  // Extrusion is in tile units scaled to device pixels at the center's
  #|  // depth (u_units), so lines thin with distance when pitched, as the map
  #|  // does. The last pixel of the half width fades out for antialiasing;
  #|  // v_half is the half width in pixels at the vertex's own depth (clip w
  #|  // grows with depth, u_depth is the center's), like MapLibre's gamma scale.
  #|  const line = program(
  #|    "in vec2 a_pos; in vec4 a_data; uniform mat4 u_matrix; uniform float u_units; uniform float u_half;" +
  #|    "uniform float u_depth; out vec2 v_edge; out vec2 v_pos; out float v_half;" +
  #|    "void main() { v_pos = a_pos + a_data.xy / 63.0 * u_half * u_units;" +
  #|    "  gl_Position = u_matrix * vec4(v_pos, 0.0, 1.0); v_edge = a_data.zw;" +
  #|    "  v_half = u_half * u_depth / gl_Position.w; }",
  #|    // v_edge is (side, along): its length reaches 1 at the outline and
  #|    // around round caps.
  #|    clip + "uniform vec4 u_color; in vec2 v_edge; in float v_half; out vec4 o;" +
  #|    "void main() { if (outside()) discard; o = u_color * clamp((1.0 - length(v_edge)) * v_half, 0.0, 1.0); }",
  #|    ["u_matrix", "u_units", "u_half", "u_depth", "u_clip", "u_color"]);
  #|  gl.enable(gl.BLEND);
  #|  gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  #|  // Circles face the viewer (MapLibre's pitch-alignment "viewport") and
  #|  // shrink with distance like the map ("pitch-scale" "map"): the quad is
  #|  // expanded around the projected center by u_size device pixels at the
  #|  // center's depth. u_inner is the fill radius over u_size; outside it is
  #|  // the stroke.
  #|  const circle = program(
  #|    "in vec2 a_pos; in vec4 a_data; uniform mat4 u_matrix; uniform vec2 u_px; uniform float u_size;" +
  #|    "uniform float u_depth; out vec2 v_extrude; out vec2 v_pos;" +
  #|    "void main() { v_pos = a_pos; v_extrude = a_data.xy / 63.0; vec4 c = u_matrix * vec4(a_pos, 0.0, 1.0);" +
  #|    "  gl_Position = c + vec4(v_extrude * u_size * u_px * u_depth, 0.0, 0.0); }",
  #|    clip + "uniform vec4 u_color; uniform vec4 u_stroke; uniform float u_size; uniform float u_inner;" +
  #|    "in vec2 v_extrude; out vec4 o;" +
  #|    "void main() { if (outside()) discard; float d = length(v_extrude); float aa = 1.0 / u_size;" +
  #|    "  float t = smoothstep(u_inner - aa, u_inner, d);" +
  #|    "  o = mix(u_color, u_stroke, t) * (1.0 - smoothstep(1.0 - aa, 1.0, d)); }",
  #|    ["u_matrix", "u_px", "u_size", "u_depth", "u_clip", "u_color", "u_stroke", "u_inner"]);
  #|  // Reused for every draw, so WebGL does not convert an array each time.
  #|  return { gl, fill, line, circle, mat: new Float32Array(16), px: [0, 0] };
  #|}

///|
extern "js" fn is_null(gl : Gl) -> Bool =
  #|(x) => x == null

///|
extern "js" fn gl_viewport(gl : Gl, width : Int32, height : Int32) -> Unit =
  #|(c, w, h) => { c.gl.viewport(0, 0, w, h); c.px = [2 / w, 2 / h]; }

///|
extern "js" fn gl_clear(gl : Gl, r : Double, g : Double, b : Double) -> Unit =
  #|(c, r, g, b) => { c.gl.clearColor(r, g, b, 1); c.gl.clear(c.gl.COLOR_BUFFER_BIT); }

///|
extern "js" fn gl_upload(
  gl : Gl,
  line : Bool,
  vertices : JsBuffer,
  indices : JsBuffer,
  count : Int32,
  index_bytes : Int32,
) -> Mesh =
  #|(c, line, vertices, indices, count, indexBytes) => {
  #|  const gl = c.gl;
  #|  const vao = gl.createVertexArray();
  #|  gl.bindVertexArray(vao);
  #|  const vbo = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
  #|  gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(0);
  #|  gl.vertexAttribPointer(0, 2, gl.SHORT, false, line ? 8 : 4, 0);
  #|  if (line) {
  #|    gl.enableVertexAttribArray(1);
  #|    gl.vertexAttribPointer(1, 4, gl.BYTE, false, 8, 4);
  #|  }
  #|  const ibo = gl.createBuffer();
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
  #|  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
  #|  gl.bindVertexArray(null);
  #|  const type = indexBytes === 2 ? gl.UNSIGNED_SHORT : gl.UNSIGNED_INT;
  #|  return { vao, vbo, ibo, count, type, bytes: vertices.byteLength + indices.byteLength };
  #|}

///|
extern "js" fn gl_release(gl : Gl, mesh : Mesh) -> Unit =
  #|(c, m) => { c.gl.deleteVertexArray(m.vao); c.gl.deleteBuffer(m.vbo); c.gl.deleteBuffer(m.ibo); }

///|
/// `clip` is (min x, min y, max x, max y) in tile units.
extern "js" fn gl_draw_fill(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> Unit =
  #|(c, m, matrix, clip, r, g, b, a) => {
  #|  const gl = c.gl, p = c.fill;
  #|  gl.useProgram(p.program);
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform4f(p.u_color, r * a, g * a, b * a, a);
  #|  gl.bindVertexArray(m.vao);
  #|  gl.drawElements(gl.TRIANGLES, m.count, m.type, 0);
  #|}

///|
extern "js" fn gl_draw_line(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  units : Double,
  depth : Double,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
  half : Double,
) -> Unit =
  #|(c, m, matrix, clip, units, depth, r, g, b, a, half) => {
  #|  const gl = c.gl, p = c.line;
  #|  gl.useProgram(p.program);
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform1f(p.u_units, units);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_half, half);
  #|  gl.uniform4f(p.u_color, r * a, g * a, b * a, a);
  #|  gl.bindVertexArray(m.vao);
  #|  gl.drawElements(gl.TRIANGLES, m.count, m.type, 0);
  #|}

///|
/// `color` and `stroke` are straight RGBA; sizes are in device pixels.
extern "js" fn gl_draw_circle(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  depth : Double,
  color : FixedArray[Double],
  stroke : FixedArray[Double],
  radius : Double,
  stroke_width : Double,
) -> Unit =
  #|(c, m, matrix, clip, depth, color, stroke, radius, strokeWidth) => {
  #|  const gl = c.gl, p = c.circle;
  #|  const size = radius + strokeWidth;
  #|  if (size <= 0) return;
  #|  // Without a stroke the edge fades to the fill color.
  #|  const s = strokeWidth > 0 ? stroke : color;
  #|  gl.useProgram(p.program);
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform2f(p.u_px, c.px[0], c.px[1]);
  #|  gl.uniform1f(p.u_size, size);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_inner, radius / size);
  #|  gl.uniform4f(p.u_color, color[0] * color[3], color[1] * color[3], color[2] * color[3], color[3]);
  #|  gl.uniform4f(p.u_stroke, s[0] * s[3], s[1] * s[3], s[2] * s[3], s[3]);
  #|  gl.bindVertexArray(m.vao);
  #|  gl.drawElements(gl.TRIANGLES, m.count, m.type, 0);
  #|}

///|
extern "js" fn mesh_bytes(mesh : Mesh) -> Int32 =
  #|(m) => m.bytes
