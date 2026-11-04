///|
/// Creates the glyph atlas texture (one byte per pixel) on first use.
extern "js" fn gl_glyph(
  gl : Gl,
  width : Int32,
  height : Int32,
  data : JsBuffer,
  x : Int32,
  y : Int32,
  w : Int32,
  h : Int32,
) -> Unit =
  #|(c, width, height, data, x, y, w, h) => {
  #|  const gl = c.gl;
  #|  if (!c.atlas) {
  #|    c.atlas = gl.createTexture();
  #|    gl.bindTexture(gl.TEXTURE_2D, c.atlas);
  #|    gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, width, height, 0, gl.RED, gl.UNSIGNED_BYTE, null);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|    c.atlasSize = [width, height];
  #|  }
  #|  gl.bindTexture(gl.TEXTURE_2D, c.atlas);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  #|  gl.texSubImage2D(gl.TEXTURE_2D, 0, x, y, w, h, gl.RED, gl.UNSIGNED_BYTE, data);
  #|}

///|
/// Uploads glyph quads after turning each vertex's glyph index and corner into atlas pixels from
/// `rects` (x, y, width, height per glyph index), with the `format` sections' colors if any
/// (docs/FORMATS.md "Symbol vertices"). Nothing is drawn until `gl_show`.
extern "js" fn gl_upload_symbols(
  gl : Gl,
  vertices : JsBuffer,
  indices : JsBuffer,
  index_bytes : Int32,
  rects : FixedArray[Int32],
  colors : JsBuffer,
) -> Mesh =
  #|(c, vertices, indices, indexBytes, rects, colors) => {
  #|  const gl = c.gl;
  #|  const v = new DataView(vertices);
  #|  for (let o = 0; o < vertices.byteLength; o += 16) {
  #|    const g = v.getUint16(o + 8, true) * 4, corner = v.getUint16(o + 10, true);
  #|    v.setUint16(o + 8, rects[g] + (corner === 1 || corner === 2 ? rects[g + 2] : 0), true);
  #|    v.setUint16(o + 10, rects[g + 1] + (corner >= 2 ? rects[g + 3] : 0), true);
  #|  }
  #|  const vao = gl.createVertexArray();
  #|  gl.bindVertexArray(vao);
  #|  const vbo = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
  #|  gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(0);
  #|  gl.vertexAttribPointer(0, 2, gl.SHORT, false, 16, 0);
  #|  gl.enableVertexAttribArray(1);
  #|  gl.vertexAttribPointer(1, 2, gl.SHORT, false, 16, 4);
  #|  gl.enableVertexAttribArray(2);
  #|  gl.vertexAttribPointer(2, 2, gl.UNSIGNED_SHORT, false, 16, 8);
  #|  gl.enableVertexAttribArray(3);
  #|  gl.vertexAttribPointer(3, 1, gl.UNSIGNED_SHORT, false, 16, 12);
  #|  // Each vertex's anchor elevation in meters, set by gl_set_heights.
  #|  const ele = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, ele);
  #|  gl.bufferData(gl.ARRAY_BUFFER, vertices.byteLength / 16 * 4, gl.DYNAMIC_DRAW);
  #|  gl.enableVertexAttribArray(4);
  #|  gl.vertexAttribPointer(4, 1, gl.FLOAT, false, 4, 0);
  #|  const colored = colors && gl.createBuffer();
  #|  if (colored) {
  #|    gl.bindBuffer(gl.ARRAY_BUFFER, colored);
  #|    gl.bufferData(gl.ARRAY_BUFFER, colors, gl.STATIC_DRAW);
  #|    gl.enableVertexAttribArray(5);
  #|    gl.vertexAttribPointer(5, 4, gl.UNSIGNED_BYTE, true, 8, 0);
  #|    gl.enableVertexAttribArray(14);
  #|    gl.vertexAttribPointer(14, 1, gl.UNSIGNED_BYTE, false, 8, 4);
  #|  }
  #|  const ibo = gl.createBuffer();
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
  #|  gl.bindVertexArray(null);
  #|  const all = indexBytes === 2 ? new Uint16Array(indices) : new Uint32Array(indices);
  #|  const type = indexBytes === 2 ? gl.UNSIGNED_SHORT : gl.UNSIGNED_INT;
  #|  return { vao, vbo, ibo, ele, vertices: vertices.byteLength / 16, all, count: 0, type, colored,
  #|    bytes: vertices.byteLength + indices.byteLength + (colors?.byteLength ?? 0) };
  #|}

///|
extern "js" fn gl_show(
  gl : Gl,
  mesh : Mesh,
  labels : JsBuffer,
  stride : Int32,
  col : Int32,
  shown : FixedArray[Bool],
  variant : FixedArray[Int32],
  order : FixedArray[Int32],
) -> Unit =
  #|(c, m, labels, stride, col, shown, variant, order) => {
  #|  const gl = c.gl;
  #|  let n = 0;
  #|  for (let i = 0; i < shown.length; i++) if (shown[i]) n += labels[i * stride + col + 2];
  #|  const out = new m.all.constructor(n);
  #|  let at = 0;
  #|  for (let k = 0; k < shown.length; k++) {
  #|    const i = order.length ? order[k] : k;
  #|    if (!shown[i]) continue;
  #|    const r = i * stride + col, count = labels[r + 2], first = labels[r + 1] + Math.min(variant[i], labels[r] - 1) * count;
  #|    out.set(m.all.subarray(first, first + count), at);
  #|    at += count;
  #|  }
  #|  gl.bindVertexArray(null);
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.ibo);
  #|  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, out, gl.DYNAMIC_DRAW);
  #|  m.count = n;
  #|}

///|
/// `u`: halo width and blur (CSS px), a halo pass of its own, opacity, gamma scale (as
/// `Renderer::draw_symbols`); `center` is the screen center's clip w; `scale` turns the
/// anchors' elevations (meters) into world pixels.
extern "js" fn gl_draw_symbols(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  dpr : Double,
  color : FixedArray[Double],
  halo : FixedArray[Double],
  u : FixedArray[Double],
  center : Double,
  scale : Double,
  along : Double,
) -> Unit =
  #|(c, m, matrix, dpr, color, halo, u, center, scale, along) => {
  #|  if (m.count === 0 || !c.atlas) return;
  #|  const gl = c.gl, p = c.symbol, pre = (loc, v) => gl.uniform4f(loc, v[0] * v[3], v[1] * v[3], v[2] * v[3], v[3]);
  #|  gl.useProgram(p.program);
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform1f(p.u_along, m.glyph ? along : 0);
  #|  gl.uniform2f(p.u_px, c.px[0], c.px[1]);
  #|  gl.uniform1f(p.u_dpr, dpr);
  #|  gl.uniform1f(p.u_center, center);
  #|  gl.uniform1f(p.u_scale, scale);
  #|  gl.uniform1f(p.u_opacity, 1);
  #|  gl.uniform1f(p.u_fill_opacity, u[3]);
  #|  gl.uniform1f(p.u_gamma_scale, m.glyph ? u[4] : 1);
  #|  const occlude = !!c.depth?.ready;
  #|  gl.uniform1i(p.u_occlude, occlude ? 1 : 0);
  #|  gl.activeTexture(gl.TEXTURE2);
  #|  gl.bindTexture(gl.TEXTURE_2D, occlude ? c.depth.texture : null);
  #|  gl.uniform1i(p.u_depth, 2);
  #|  gl.uniform2f(p.u_atlas, c.atlasSize[0], c.atlasSize[1]);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, c.atlas);
  #|  gl.uniform1i(p.u_glyphs, 0);
  #|  pre(p.u_color, color);
  #|  pre(p.u_halo_color, halo);
  #|  gl.bindVertexArray(m.vao);
  #|  if (!m.shift) gl.vertexAttrib2f(15, 0, 0);
  #|  if (!m.colored) gl.vertexAttrib1f(14, 0);
  #|  const hasHalo = u[0] > 0;
  #|  if (hasHalo && u[2]) {
  #|    gl.uniform3f(p.u_halo, u[0], u[1], 0);
  #|    gl.drawElements(gl.TRIANGLES, m.count, m.type, 0);
  #|  }
  #|  gl.uniform3f(p.u_halo, hasHalo && !u[2] ? u[0] : 0, u[1], 1);
  #|  gl.drawElements(gl.TRIANGLES, m.rangeCount ?? m.count, m.type, m.rangeOffset ?? 0);
  #|}

///|
/// `u`: dpr, center clip w, elevation scale, size, perspective, pitch, rotate, angle,
/// tile units per px, opacity, sdf, halo width, blur, gamma scale, linear, along
/// (colors straight RGBA). MapLibre draws a halo wider than 1 px in its own pass.
extern "js" fn gl_draw_icons(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  u : FixedArray[Double],
  color : FixedArray[Double],
  halo : FixedArray[Double],
) -> Unit =
  #|(c, m, matrix, u, color, halo) => {
  #|  if (m.count === 0 || !c.icons) return;
  #|  const gl = c.gl, p = c.icon, pre = (loc, v) => gl.uniform4f(loc, v[0] * v[3], v[1] * v[3], v[2] * v[3], v[3]);
  #|  gl.useProgram(p.program);
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform2f(p.u_px, c.px[0], c.px[1]);
  #|  ["u_dpr", "u_center", "u_scale", "u_size", "u_persp", "u_pitch", "u_rotate", "u_angle", "u_units", "u_opacity", "u_sdf"]
  #|    .forEach((name, i) => (i === 4 || i === 5 || i === 6 || i === 10 ? gl.uniform1i(p[name], u[i]) : gl.uniform1f(p[name], u[i])));
  #|  gl.uniform1f(p.u_gamma_scale, u[13]);
  #|  gl.uniform1f(p.u_along, m.glyph && u[15] ? 1 : 0);
  #|  const occlude = !!c.depth?.ready;
  #|  gl.uniform1i(p.u_occlude, occlude ? 1 : 0);
  #|  gl.activeTexture(gl.TEXTURE2);
  #|  gl.bindTexture(gl.TEXTURE_2D, occlude ? c.depth.texture : null);
  #|  gl.uniform1i(p.u_depth, 2);
  #|  gl.uniform2f(p.u_atlas, c.iconsSize[0], c.iconsSize[1]);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, c.icons);
  #|  const filter = u[14] ? gl.LINEAR : gl.NEAREST;
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
  #|  gl.uniform1i(p.u_glyphs, 0);
  #|  pre(p.u_color, color);
  #|  pre(p.u_halo_color, halo);
  #|  gl.bindVertexArray(m.vao);
  #|  if (!m.shift) gl.vertexAttrib2f(15, 0, 0);
  #|  const hasHalo = u[10] && u[11] > 0;
  #|  if (hasHalo && u[11] > 1) {
  #|    gl.uniform3f(p.u_halo, u[11], u[12], 0);
  #|    gl.drawElements(gl.TRIANGLES, m.count, m.type, 0);
  #|  }
  #|  gl.uniform3f(p.u_halo, hasHalo && u[11] <= 1 ? u[11] : 0, u[12], 1);
  #|  gl.drawElements(gl.TRIANGLES, m.count, m.type, 0);
  #|}

///|
/// Sets the anchor elevation (meters) of every vertex of each label: `heights`
/// has one per label, whose indices are at `labels` (as for `gl_show`).
extern "js" fn gl_set_heights(
  gl : Gl,
  mesh : Mesh,
  labels : JsBuffer,
  stride : Int32,
  col : Int32,
  heights : FixedArray[Double],
) -> Unit =
  #|(c, m, labels, stride, col, heights) => {
  #|  const gl = c.gl, out = new Float32Array(m.vertices);
  #|  for (let i = 0; i < heights.length; i++) {
  #|    const r = i * stride + col, first = labels[r + 1], end = first + labels[r + 2] * labels[r];
  #|    for (let k = first; k < end; k++) out[m.all[k]] = heights[i];
  #|  }
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, m.ele);
  #|  gl.bufferData(gl.ARRAY_BUFFER, out, gl.DYNAMIC_DRAW);
  #|}

///|
/// Sets where each glyph of a mesh of labels along lines lies (`glyphs`: x, y in
/// tile units and angle per glyph quad, x below -1e8 hiding it).
extern "js" fn gl_set_glyphs(
  gl : Gl,
  mesh : Mesh,
  glyphs : FixedArray[Double],
) -> Unit =
  #|(c, m, glyphs) => {
  #|  const gl = c.gl;
  #|  m.glyphData ??= new Float32Array(m.vertices * 3);
  #|  const out = m.glyphData, n = Math.min(glyphs.length / 3, m.vertices / 4);
  #|  for (let g = 0; g < n; g++) {
  #|    for (let o = g * 12; o < g * 12 + 12; o += 3) {
  #|      out[o] = glyphs[g * 3];
  #|      out[o + 1] = glyphs[g * 3 + 1];
  #|      out[o + 2] = glyphs[g * 3 + 2];
  #|    }
  #|  }
  #|  if (!m.glyph) {
  #|    m.glyph = gl.createBuffer();
  #|    gl.bindVertexArray(m.vao);
  #|    gl.bindBuffer(gl.ARRAY_BUFFER, m.glyph);
  #|    gl.enableVertexAttribArray(13);
  #|    gl.vertexAttribPointer(13, 3, gl.FLOAT, false, 12, 0);
  #|    gl.bindVertexArray(null);
  #|  }
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, m.glyph);
  #|  gl.bufferData(gl.ARRAY_BUFFER, out, gl.DYNAMIC_DRAW);
  #|}

///|
/// Sets each label's shift (`shifts`, x and y in CSS px per label of `labels`),
/// on all its variants' vertices.
extern "js" fn gl_set_shifts(
  gl : Gl,
  mesh : Mesh,
  labels : JsBuffer,
  stride : Int32,
  col : Int32,
  shifts : FixedArray[Double],
) -> Unit =
  #|(c, m, labels, stride, col, shifts) => {
  #|  const gl = c.gl, out = new Float32Array(m.vertices * 2);
  #|  for (let i = 0; i < shifts.length / 2; i++) {
  #|    const r = i * stride + col, first = labels[r + 1], end = first + labels[r + 2] * labels[r];
  #|    for (let k = first; k < end; k++) {
  #|      out[m.all[k] * 2] = shifts[i * 2];
  #|      out[m.all[k] * 2 + 1] = shifts[i * 2 + 1];
  #|    }
  #|  }
  #|  if (!m.shift) {
  #|    m.shift = gl.createBuffer();
  #|    gl.bindVertexArray(m.vao);
  #|    gl.bindBuffer(gl.ARRAY_BUFFER, m.shift);
  #|    gl.enableVertexAttribArray(15);
  #|    gl.vertexAttribPointer(15, 2, gl.FLOAT, false, 8, 0);
  #|    gl.bindVertexArray(null);
  #|  }
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, m.shift);
  #|  gl.bufferData(gl.ARRAY_BUFFER, out, gl.DYNAMIC_DRAW);
  #|}
