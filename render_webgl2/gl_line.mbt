///|
extern "js" fn gl_draw_line(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  units : Double,
  depth : Double,
  dpr : Double,
  blur : Double,
) -> Unit =
  #|(c, m, matrix, clip, units, depth, dpr, blur) => {
  #|  const gl = c.gl, p = c.line;
  #|  c.place(p, matrix, clip);
  #|  gl.uniform1f(p.u_units, units);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_dpr, dpr);
  #|  gl.uniform1f(p.u_blur, blur);
  #|  c.draw(m);
  #|}

///|
/// Adds a line mesh's distances along its lines (Uint16 per vertex) as `a_dist`.
extern "js" fn gl_upload_distances(
  gl : Gl,
  mesh : Mesh,
  distances : JsBuffer,
) -> Unit =
  #|(c, m, data) => {
  #|  const gl = c.gl;
  #|  gl.bindVertexArray(m.vao);
  #|  m.dist = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, m.dist);
  #|  gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(13);
  #|  gl.vertexAttribPointer(13, 1, gl.UNSIGNED_SHORT, false, 2, 0);
  #|  gl.bindVertexArray(null);
  #|}

///|
/// Adds a line mesh's offset normals (two Int8s per vertex) as `a_offset`.
extern "js" fn gl_upload_offsets(
  gl : Gl,
  mesh : Mesh,
  offsets : JsBuffer,
) -> Unit =
  #|(c, m, data) => {
  #|  const gl = c.gl;
  #|  gl.bindVertexArray(m.vao);
  #|  m.offsets = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, m.offsets);
  #|  gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(2);
  #|  gl.vertexAttribPointer(2, 2, gl.BYTE, false, 2, 0);
  #|  gl.bindVertexArray(null);
  #|}

///|
/// Adds a line mesh's progress (per vertex, f32 share of its line and f32 row
/// of its gradient) as `a_progress`.
extern "js" fn gl_upload_progress(
  gl : Gl,
  mesh : Mesh,
  progress : JsBuffer,
) -> Unit =
  #|(c, m, data) => {
  #|  const gl = c.gl;
  #|  gl.bindVertexArray(m.vao);
  #|  m.progress = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, m.progress);
  #|  gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(14);
  #|  gl.vertexAttribPointer(14, 2, gl.FLOAT, false, 8, 0);
  #|  gl.bindVertexArray(null);
  #|}

///|
/// A line gradient's color ramp on the GPU: a row per line of a tile.
#external
pub type Gradient

///|
/// Uploads a color ramp (straight RGBA bytes, `width` x `height`, premultiplied
/// and rounded as MapLibre's `premultiplyAlpha`), clamped at its edges and
/// filtered linearly, or `nearest` for a step ramp.
extern "js" fn gl_upload_gradient(
  gl : Gl,
  pixels : FixedArray[Byte],
  width : Int32,
  height : Int32,
  nearest : Bool,
) -> Gradient =
  #|(c, data, w, h, nearest) => {
  #|  const gl = c.gl, t = gl.createTexture(), f = nearest ? gl.NEAREST : gl.LINEAR;
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, t);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, f);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, f);
  #|  const pre = new Uint8Array(data.length);
  #|  for (let i = 0; i < data.length; i += 4) {
  #|    const a = data[i + 3];
  #|    for (let k = 0; k < 3; k++) pre[i + k] = Math.round(data[i + k] * a / 255);
  #|    pre[i + 3] = a;
  #|  }
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, pre);
  #|  return { texture: t, rows: h };
  #|}

///|
extern "js" fn gl_release_gradient(gl : Gl, g : Gradient) -> Unit =
  #|(c, g) => { c.gl.deleteTexture(g.texture); if (g.elevations) c.gl.deleteTexture(g.elevations); }

///|
/// Draws a line with gradient `g` (see the `lineGradient` program).
extern "js" fn gl_draw_line_gradient(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  units : Double,
  depth : Double,
  dpr : Double,
  blur : Double,
  g : Gradient,
) -> Unit =
  #|(c, m, matrix, clip, units, depth, dpr, blur, g) => {
  #|  const gl = c.gl, p = c.lineGradient;
  #|  c.place(p, matrix, clip);
  #|  gl.uniform1f(p.u_units, units);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_dpr, dpr);
  #|  gl.uniform1f(p.u_blur, blur);
  #|  gl.uniform1f(p.u_rows, g.rows);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, g.texture);
  #|  gl.uniform1i(p.u_image, 0);
  #|  c.draw(m);
  #|}

///|
/// Uploads the dash atlas (one byte per pixel) into texture unit 0, created on
/// first use, wrapping and filtered linearly as MapLibre's.
extern "js" fn gl_dash_atlas(
  gl : Gl,
  data : FixedArray[Byte],
  width : Int32,
  height : Int32,
) -> Unit =
  #|(c, data, w, h) => {
  #|  const gl = c.gl;
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  if (!c.dash) {
  #|    c.dash = gl.createTexture();
  #|    gl.bindTexture(gl.TEXTURE_2D, c.dash);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  #|  } else gl.bindTexture(gl.TEXTURE_2D, c.dash);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, w, h, 0, gl.RED, gl.UNSIGNED_BYTE, data);
  #|}

///|
/// Draws a dashed line with `program` (`lineDash`, or `lineDashFeature` for
/// dashes by feature): `dash` and `floor` are its u_dash and u_floor.
extern "js" fn gl_draw_line_dash(
  gl : Gl,
  program : String,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  units : Double,
  depth : Double,
  dpr : Double,
  blur : Double,
  dash : FixedArray[Double],
  floor : FixedArray[Double],
) -> Unit =
  #|(c, name, m, matrix, clip, units, depth, dpr, blur, dash, floor) => {
  #|  const gl = c.gl, p = c[name];
  #|  c.place(p, matrix, clip);
  #|  gl.uniform1f(p.u_units, units);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_dpr, dpr);
  #|  gl.uniform1f(p.u_blur, blur);
  #|  gl.uniform4f(p.u_dash, dash[0], dash[1], dash[2], dash[3]);
  #|  gl.uniform2f(p.u_floor, floor[0], floor[1]);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, c.dash);
  #|  gl.uniform1i(p.u_image, 0);
  #|  c.draw(m);
  #|}

///|
/// Adds a line mesh's dashes by feature as `a_dash` (see the `lineDashFeature`
/// program): `marks` four u16s per vertex naming patterns of `entries` (row times
/// 64 plus height, and width each; a width of -1 where the atlas has none).
extern "js" fn gl_upload_feature_dashes(
  gl : Gl,
  mesh : Mesh,
  marks : JsBuffer,
  entries : FixedArray[Double],
) -> Unit =
  #|(c, m, data, entries) => {
  #|  const gl = c.gl, marks = new Uint16Array(data), n = marks.length / 4, out = new Float32Array(n * 4);
  #|  // MapLibre's dasharray attributes are Uint16s, so a pattern's length is truncated there.
  #|  const width = (k) => (k * 2 + 1 < entries.length && entries[k * 2 + 1] >= 0 ? Math.trunc(entries[k * 2 + 1]) & 0xffff : -1);
  #|  for (let i = 0; i < n; i++) {
  #|    const lo = marks[i * 4], mid = marks[i * 4 + 1], hi = marks[i * 4 + 2], w = width(mid);
  #|    out[i * 4] = w < 0 ? 0 : entries[mid * 2];
  #|    out[i * 4 + 1] = w;
  #|    out[i * 4 + 2] = width(lo) < 0 ? w : Math.min(w, width(lo));
  #|    out[i * 4 + 3] = width(hi) < 0 ? w : Math.min(w, width(hi));
  #|  }
  #|  gl.bindVertexArray(m.vao);
  #|  m.dashes = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, m.dashes);
  #|  gl.bufferData(gl.ARRAY_BUFFER, out, gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(15);
  #|  gl.vertexAttribPointer(15, 4, gl.FLOAT, false, 16, 0);
  #|  gl.bindVertexArray(null);
  #|}
