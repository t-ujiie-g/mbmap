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
extern "js" fn is_null(gl : Gl) -> Bool =
  #|(x) => x == null

///|
extern "js" fn gl_viewport(gl : Gl, width : Int32, height : Int32) -> Unit =
  #|(c, w, h) => { c.gl.viewport(0, 0, w, h); c.px = [2 / w, 2 / h]; c.size = [w, h]; }

///|
extern "js" fn gl_clear(gl : Gl, r : Double, g : Double, b : Double) -> Unit =
  #|(c, r, g, b) => { c.gl.clearColor(r, g, b, 1); c.gl.clear(c.gl.COLOR_BUFFER_BIT | c.gl.DEPTH_BUFFER_BIT); }

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
  #|  return { vao, vbo, ibo, count, type };
  #|}

///|
extern "js" fn gl_release(gl : Gl, mesh : Mesh) -> Unit =
  #|(c, m) => {
  #|  if (m.elev) c.gl.deleteTexture(m.elev);
  #|  if (m.relief) c.gl.deleteTexture(m.relief);
  #|  if (m.texture) { c.gl.deleteTexture(m.texture); return; }
  #|  c.gl.deleteVertexArray(m.vao); c.gl.deleteBuffer(m.vbo); c.gl.deleteBuffer(m.ibo);
  #|  if (m.outline) c.gl.deleteBuffer(m.outline);
  #|  if (m.dist) c.gl.deleteBuffer(m.dist);
  #|  if (m.offsets) c.gl.deleteBuffer(m.offsets);
  #|  if (m.progress) c.gl.deleteBuffer(m.progress);
  #|  if (m.ele) c.gl.deleteBuffer(m.ele);
  #|  if (m.shift) c.gl.deleteBuffer(m.shift);
  #|  if (m.glyph) c.gl.deleteBuffer(m.glyph);
  #|  if (m.colored) c.gl.deleteBuffer(m.colored);
  #|}

///|
/// One draw's paint by slot (`@style.SLOT_*`): per slot, a constant (straight
/// RGBA or a number) or a layer's per-vertex values from where its zoom
/// position starts.
#external
pub type PaintSlots

///|
/// A layer's per-vertex paint on the GPU (docs/FORMATS.md, "Vertex paint").
#external
pub type PaintBuffer

///|
extern "js" fn paint_slots_new() -> PaintSlots = "() => []"

///|
extern "js" fn paint_slots_constant(
  slots : PaintSlots,
  slot : Int32,
  a : Double,
  b : Double,
  c : Double,
  d : Double,
) -> Unit = "(s, slot, a, b, c, d) => { s[slot] = { value: [a, b, c, d] }; }"

///|
extern "js" fn paint_slots_buffer(
  slots : PaintSlots,
  slot : Int32,
  buffer : PaintBuffer,
  offset : Int32,
  stride : Int32,
  t : Double,
  single : Bool,
) -> Unit =
  #|(s, slot, buffer, offset, stride, t, single) => { s[slot] = { buffer, offset, stride, t, single }; }

///|
extern "js" fn gl_upload_paint(gl : Gl, data : JsBuffer) -> PaintBuffer =
  #|(c, data) => {
  #|  const gl = c.gl, b = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, b);
  #|  gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
  #|  return b;
  #|}

///|
extern "js" fn gl_release_paint(gl : Gl, buffer : PaintBuffer) -> Unit =
  #|(c, b) => c.gl.deleteBuffer(b)

///|
/// Binds the first `count` `slots` to the bound vertex array and `program`: colors take
/// two attributes (start, next), numbers a vec2 (a `single` value: read once, t 0).
/// Every slot is set, as layers share vertex arrays.
extern "js" fn gl_bind_paint(
  gl : Gl,
  program : String,
  slots : PaintSlots,
  count : Int32,
) -> Unit =
  #|(c, name, slots, count) => {
  #|  const gl = c.gl, p = c[name], LOC = [[5, 6], [7], [8], [9, 10], [11], [12]], ts = new Float32Array(6);
  #|  for (let k = 0; k < count; k++) {
  #|    const s = slots[k], locs = LOC[k];
  #|    if (s.buffer) {
  #|      ts[k] = s.t;
  #|      gl.bindBuffer(gl.ARRAY_BUFFER, s.buffer);
  #|      locs.forEach((loc, h) => {
  #|        gl.enableVertexAttribArray(loc);
  #|        if (locs.length === 2) gl.vertexAttribPointer(loc, 4, gl.UNSIGNED_BYTE, true, s.stride, s.offset + (s.single ? 0 : h * 4));
  #|        else gl.vertexAttribPointer(loc, s.single ? 1 : 2, gl.FLOAT, false, s.stride, s.offset);
  #|      });
  #|    } else {
  #|      const v = s.value;
  #|      for (const loc of locs) {
  #|        gl.disableVertexAttribArray(loc);
  #|        if (locs.length === 2) gl.vertexAttrib4f(loc, v[0], v[1], v[2], v[3]);
  #|        else gl.vertexAttrib2f(loc, v[0], v[0]);
  #|      }
  #|    }
  #|  }
  #|  gl.uniform1fv(p.u_t, ts);
  #|}

///|
/// `clip` is (min x, min y, max x, max y) in tile units.
extern "js" fn gl_draw_fill(
  gl : Gl,
  program : String,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
) -> Unit =
  #|(c, name, m, matrix, clip) => {
  #|  const gl = c.gl, p = c[name];
  #|  c.place(p, matrix, clip);
  #|  c.draw(m);
  #|}

///|
extern "js" fn gl_upload_outline(
  gl : Gl,
  mesh : Mesh,
  indices : JsBuffer,
  count : Int32,
) -> Unit =
  #|(c, m, indices, count) => {
  #|  const gl = c.gl;
  #|  m.outline = gl.createBuffer();
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.outline);
  #|  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
  #|  m.outlineCount = count;
  #|}

///|
/// Draws `mesh`'s outline as lines (with the program and vertex array bound),
/// then gives the vertex array back its triangles.
extern "js" fn gl_draw_outline(
  gl : Gl,
  program : String,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
) -> Unit =
  #|(c, name, m, matrix, clip) => {
  #|  const gl = c.gl, p = c[name];
  #|  if (!m.outline) return;
  #|  c.place(p, matrix, clip);
  #|  gl.uniform2f(p.u_world, 2 / c.px[0], 2 / c.px[1]);
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.outline);
  #|  gl.drawElements(gl.LINES, m.outlineRange ?? m.outlineCount, m.type, m.outlineOffset ?? 0);
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.ibo);
  #|}

///|
extern "js" fn gl_draw_circle(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  depth : Double,
  dpr : Double,
  units : Double,
  look : FixedArray[Double],
) -> Unit =
  #|(c, m, matrix, clip, depth, dpr, units, look) => {
  #|  const gl = c.gl, p = c.circle;
  #|  c.place(p, matrix, clip);
  #|  gl.uniform2f(p.u_px, c.px[0], c.px[1]);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_dpr, dpr);
  #|  gl.uniform1f(p.u_units, units);
  #|  gl.uniform1i(p.u_scale, look[0]);
  #|  gl.uniform1i(p.u_pitch, look[1]);
  #|  gl.uniform1f(p.u_blur, look[2]);
  #|  c.draw(m);
  #|}

///|
/// Uses `program` and binds `mesh`'s vertex array with `slots`.
extern "js" fn gl_use(gl : Gl, program : String, mesh : Mesh) -> Unit =
  #|(c, name, m) => { c.gl.useProgram(c[name].program); c.gl.bindVertexArray(m.vao); }

///|
/// An offscreen draw target: a framebuffer with a color texture.
#external
pub type Target
