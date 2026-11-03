///|
extern "js" fn gl_draw_line(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  units : Double,
  depth : Double,
  dpr : Double,
) -> Unit =
  #|(c, m, matrix, clip, units, depth, dpr) => {
  #|  const gl = c.gl, p = c.line;
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform1f(p.u_units, units);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_dpr, dpr);
  #|  gl.drawElements(gl.TRIANGLES, m.rangeCount ?? m.count, m.type, m.rangeOffset ?? 0);
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
  #|  m.bytes += data.byteLength;
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
  #|  m.bytes += data.byteLength;
  #|}

///|
/// A line gradient's color ramp on the GPU: a row per line of a tile.
#external
pub type Gradient

///|
/// Uploads a color ramp (straight RGBA bytes, `width` x `height`, premultiplied
/// by the upload as MapLibre's), clamped at its edges and filtered linearly, or
/// `nearest` for a step ramp.
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
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
  #|  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
  #|  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  #|  return { texture: t, rows: h };
  #|}

///|
extern "js" fn gl_release_gradient(gl : Gl, g : Gradient) -> Unit =
  #|(c, g) => c.gl.deleteTexture(g.texture)

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
  g : Gradient,
) -> Unit =
  #|(c, m, matrix, clip, units, depth, dpr, g) => {
  #|  const gl = c.gl, p = c.lineGradient;
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform1f(p.u_units, units);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_dpr, dpr);
  #|  gl.uniform1f(p.u_rows, g.rows);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, g.texture);
  #|  gl.uniform1i(p.u_image, 0);
  #|  gl.drawElements(gl.TRIANGLES, m.rangeCount ?? m.count, m.type, m.rangeOffset ?? 0);
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
/// Draws a dashed line (see the `lineDash` program): `dash` and `floor` are
/// its u_dash and u_floor.
extern "js" fn gl_draw_line_dash(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  units : Double,
  depth : Double,
  dpr : Double,
  dash : FixedArray[Double],
  floor : FixedArray[Double],
) -> Unit =
  #|(c, m, matrix, clip, units, depth, dpr, dash, floor) => {
  #|  const gl = c.gl, p = c.lineDash;
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform1f(p.u_units, units);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_dpr, dpr);
  #|  gl.uniform4f(p.u_dash, dash[0], dash[1], dash[2], dash[3]);
  #|  gl.uniform2f(p.u_floor, floor[0], floor[1]);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, c.dash);
  #|  gl.uniform1i(p.u_image, 0);
  #|  gl.drawElements(gl.TRIANGLES, m.rangeCount ?? m.count, m.type, m.rangeOffset ?? 0);
  #|}
