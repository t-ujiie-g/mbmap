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
  #|  const fill = program(
  #|    "in vec2 a_pos; uniform vec4 u_tile;" +
  #|    "void main() { gl_Position = vec4(a_pos * u_tile.xy + u_tile.zw, 0.0, 1.0); }",
  #|    "uniform vec4 u_color; out vec4 o; void main() { o = u_color; }",
  #|    ["u_tile", "u_color"]);
  #|  // Extrusion is in screen pixels, so widths stay constant across zooms;
  #|  // the last pixel of the half width fades out for antialiasing.
  #|  const line = program(
  #|    "in vec2 a_pos; in vec4 a_data; uniform vec4 u_tile; uniform vec2 u_px; uniform float u_half;" +
  #|    "out vec2 v_edge;" +
  #|    "void main() { vec2 e = a_data.xy / 63.0 * u_half;" +
  #|    "  gl_Position = vec4(a_pos * u_tile.xy + u_tile.zw + e * u_px, 0.0, 1.0); v_edge = a_data.zw; }",
  #|    // v_edge is (side, along): its length reaches 1 at the outline and
  #|    // around round caps.
  #|    "uniform vec4 u_color; uniform float u_half; in vec2 v_edge; out vec4 o;" +
  #|    "void main() { o = u_color * clamp((1.0 - length(v_edge)) * u_half, 0.0, 1.0); }",
  #|    ["u_tile", "u_px", "u_half", "u_color"]);
  #|  gl.enable(gl.BLEND);
  #|  gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  #|  return { gl, fill, line, px: [0, 0] };
  #|}

///|
extern "js" fn is_null(gl : Gl) -> Bool =
  #|(x) => x == null

///|
extern "js" fn gl_viewport(gl : Gl, width : Int32, height : Int32) -> Unit =
  #|(c, w, h) => { c.gl.viewport(0, 0, w, h); c.px = [2 / w, -2 / h]; }

///|
extern "js" fn gl_clear(gl : Gl, r : Double, g : Double, b : Double) -> Unit =
  #|(c, r, g, b) => { c.gl.disable(c.gl.SCISSOR_TEST); c.gl.clearColor(r, g, b, 1); c.gl.clear(c.gl.COLOR_BUFFER_BIT); }

///|
extern "js" fn gl_scissor(
  gl : Gl,
  x : Int32,
  y : Int32,
  w : Int32,
  h : Int32,
) -> Unit =
  #|(c, x, y, w, h) => { c.gl.enable(c.gl.SCISSOR_TEST); c.gl.scissor(x, y, w, h); }

///|
extern "js" fn gl_no_scissor(gl : Gl) -> Unit =
  #|(c) => c.gl.disable(c.gl.SCISSOR_TEST)

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
extern "js" fn gl_draw_fill(
  gl : Gl,
  mesh : Mesh,
  sx : Double,
  sy : Double,
  tx : Double,
  ty : Double,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> Unit =
  #|(c, m, sx, sy, tx, ty, r, g, b, a) => {
  #|  const gl = c.gl, p = c.fill;
  #|  gl.useProgram(p.program);
  #|  gl.uniform4f(p.u_tile, sx, sy, tx, ty);
  #|  gl.uniform4f(p.u_color, r * a, g * a, b * a, a);
  #|  gl.bindVertexArray(m.vao);
  #|  gl.drawElements(gl.TRIANGLES, m.count, m.type, 0);
  #|}

///|
extern "js" fn gl_draw_line(
  gl : Gl,
  mesh : Mesh,
  sx : Double,
  sy : Double,
  tx : Double,
  ty : Double,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
  half : Double,
) -> Unit =
  #|(c, m, sx, sy, tx, ty, r, g, b, a, half) => {
  #|  const gl = c.gl, p = c.line;
  #|  gl.useProgram(p.program);
  #|  gl.uniform4f(p.u_tile, sx, sy, tx, ty);
  #|  gl.uniform2f(p.u_px, c.px[0], c.px[1]);
  #|  gl.uniform1f(p.u_half, half);
  #|  gl.uniform4f(p.u_color, r * a, g * a, b * a, a);
  #|  gl.bindVertexArray(m.vao);
  #|  gl.drawElements(gl.TRIANGLES, m.count, m.type, 0);
  #|}

///|
extern "js" fn mesh_bytes(mesh : Mesh) -> Int32 =
  #|(m) => m.bytes
