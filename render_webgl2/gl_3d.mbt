///|
/// Adds a DEM tile's elevations (`size` x `size` f32s) to its slopes mesh as a
/// float texture, for terrain.
extern "js" fn gl_add_elevations(
  gl : Gl,
  mesh : Mesh,
  elevations : JsBuffer,
  size : Int32,
) -> Unit =
  #|(c, m, data, size) => {
  #|  const gl = c.gl;
  #|  if (m.elev) gl.deleteTexture(m.elev);
  #|  m.elev = gl.createTexture();
  #|  gl.bindTexture(gl.TEXTURE_2D, m.elev);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.R32F, size, size, 0, gl.RED, gl.FLOAT, data);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  #|}

///|
extern "js" fn gl_target_new(gl : Gl, size : Int32) -> Target =
  #|(c, size) => {
  #|  const gl = c.gl;
  #|  const texture = gl.createTexture();
  #|  gl.bindTexture(gl.TEXTURE_2D, texture);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, size, size, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|  const fb = gl.createFramebuffer();
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  #|  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, c.out ?? null);
  #|  return { fb, texture, size };
  #|}

///|
extern "js" fn gl_target_release(gl : Gl, target : Target) -> Unit =
  #|(c, t) => { c.gl.deleteFramebuffer(t.fb); c.gl.deleteTexture(t.texture); }

///|
/// Draws into `target` from now on (cleared to an opaque color), or back into
/// the canvas of `width` x `height` when `target` is null.
extern "js" fn gl_target_begin(
  gl : Gl,
  target : Target,
  r : Double,
  g : Double,
  b : Double,
) -> Unit =
  #|(c, t, r, g, b) => {
  #|  const gl = c.gl;
  #|  c.saved ??= c.size.slice();
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, t.fb);
  #|  gl.viewport(0, 0, t.size, t.size);
  #|  c.px = [2 / t.size, 2 / t.size];
  #|  gl.clearColor(r, g, b, 1);
  #|  gl.clear(gl.COLOR_BUFFER_BIT);
  #|}

///|
extern "js" fn gl_target_end(gl : Gl) -> Unit =
  #|(c) => {
  #|  const gl = c.gl, [w, h] = c.saved ?? c.size;
  #|  c.saved = null;
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, c.out ?? null);
  #|  gl.viewport(0, 0, w, h);
  #|  c.px = [2 / w, 2 / h];
  #|}

///|
/// Clears the canvas's depth for a frame with terrain.
extern "js" fn gl_clear_depth(gl : Gl) -> Unit =
  #|(c) => { c.gl.clear(c.gl.DEPTH_BUFFER_BIT); }

///|
/// Draws a terrain tile: the grid raised by `mesh`'s elevations times `scale`
/// (world pixels per meter, exaggerated), covered by `target`'s picture, with
/// depth testing.
extern "js" fn gl_draw_terrain(
  gl : Gl,
  mesh : Mesh,
  target : Target,
  matrix : FixedArray[Double],
  scale : Double,
  skirt : Double,
  per_meter : Double,
  dem : FixedArray[Double],
  fog : FixedArray[Double],
  fog_color : FixedArray[Double],
  horizon : FixedArray[Double],
) -> Unit =
  #|(c, m, t, matrix, scale, skirt, perMeter, dem, fog, fogColor, horizon) => {
  #|  if (!m.elev) return;
  #|  const gl = c.gl, p = c.terrain;
  #|  gl.useProgram(p.program);
  #|  c.place(p, matrix);
  #|  gl.uniform1f(p.u_scale, scale);
  #|  gl.uniform1f(p.u_skirt, skirt);
  #|  gl.uniform1f(p.u_per_meter, perMeter);
  #|  gl.uniform3f(p.u_dem, dem[0], dem[1], dem[2]);
  #|  gl.uniform2f(p.u_fog, fog[0], fog[1]);
  #|  gl.uniform3f(p.u_fog_blend, fog[2], fog[3], fog[4]);
  #|  gl.uniform4f(p.u_fog_color, fogColor[0], fogColor[1], fogColor[2], fogColor[3]);
  #|  gl.uniform4f(p.u_horizon_color, horizon[0], horizon[1], horizon[2], horizon[3]);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, m.elev);
  #|  gl.uniform1i(p.u_elev, 0);
  #|  gl.activeTexture(gl.TEXTURE1);
  #|  gl.bindTexture(gl.TEXTURE_2D, t.texture);
  #|  gl.uniform1i(p.u_image, 1);
  #|  gl.enable(gl.DEPTH_TEST);
  #|  gl.depthFunc(gl.LEQUAL);
  #|  gl.disable(gl.BLEND);
  #|  gl.bindVertexArray(c.grid.vao);
  #|  gl.drawElements(gl.TRIANGLES, c.grid.count, gl.UNSIGNED_SHORT, 0);
  #|  gl.enable(gl.BLEND);
  #|  gl.disable(gl.DEPTH_TEST);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|}

///|
extern "js" fn gl_draw_sky(
  gl : Gl,
  horizon_y : Double,
  blend : Double,
  sky : FixedArray[Double],
  horizon : FixedArray[Double],
) -> Unit =
  #|(c, y, blend, sky, horizon) => {
  #|  const gl = c.gl, p = c.sky;
  #|  gl.useProgram(p.program);
  #|  gl.uniform1f(p.u_horizon, y);
  #|  gl.uniform1f(p.u_blend, blend);
  #|  gl.uniform4f(p.u_sky, sky[0], sky[1], sky[2], sky[3]);
  #|  gl.uniform4f(p.u_horizon_color, horizon[0], horizon[1], horizon[2], horizon[3]);
  #|  gl.bindVertexArray(c.empty);
  #|  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  #|}

///|
/// Draws into the terrain depth target (the canvas's size, depth only) from now
/// on, cleared, or back into the canvas; symbols drawn after `end` fade behind
/// what was drawn into it, until `gl_depth_reset`.
extern "js" fn gl_depth_begin(gl : Gl) -> Unit =
  #|(c) => {
  #|  const gl = c.gl, [w, h] = c.size;
  #|  let d = c.depth;
  #|  if (!d || d.w !== w || d.h !== h) {
  #|    if (d) { gl.deleteFramebuffer(d.fb); gl.deleteTexture(d.texture); }
  #|    const texture = gl.createTexture();
  #|    gl.bindTexture(gl.TEXTURE_2D, texture);
  #|    gl.texImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT24, w, h, 0, gl.DEPTH_COMPONENT, gl.UNSIGNED_INT, null);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|    const fb = gl.createFramebuffer();
  #|    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  #|    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, texture, 0);
  #|    d = c.depth = { fb, texture, w, h, ready: false };
  #|  }
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, d.fb);
  #|  gl.clear(gl.DEPTH_BUFFER_BIT);
  #|  d.ready = true;
  #|}

///|
extern "js" fn gl_depth_end(gl : Gl) -> Unit =
  #|(c) => { c.gl.bindFramebuffer(c.gl.FRAMEBUFFER, c.out ?? null); }

///|
extern "js" fn gl_depth_reset(gl : Gl) -> Unit =
  #|(c) => { if (c.depth) c.depth.ready = false; }

///|
/// Uploads a fill-extrusion entry (`@worker.EXTRUSION_VERTEX_BYTES` per
/// vertex), with a ground height of 0 m under every vertex.
extern "js" fn gl_upload_extrusion(
  gl : Gl,
  vertices : JsBuffer,
  indices : JsBuffer,
  count : Int32,
  index_bytes : Int32,
) -> Mesh =
  #|(c, vertices, indices, count, indexBytes) => {
  #|  const gl = c.gl, n = vertices.byteLength / 24;
  #|  const vao = gl.createVertexArray();
  #|  gl.bindVertexArray(vao);
  #|  const vbo = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
  #|  gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(0);
  #|  gl.vertexAttribPointer(0, 2, gl.SHORT, false, 24, 0);
  #|  gl.enableVertexAttribArray(1);
  #|  gl.vertexAttribIPointer(1, 4, gl.SHORT, 24, 4);
  #|  gl.enableVertexAttribArray(3);
  #|  gl.vertexAttribPointer(3, 4, gl.UNSIGNED_SHORT, false, 24, 16);
  #|  const ele = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, ele);
  #|  gl.bufferData(gl.ARRAY_BUFFER, n * 4, gl.DYNAMIC_DRAW);
  #|  gl.enableVertexAttribArray(4);
  #|  gl.vertexAttribPointer(4, 1, gl.FLOAT, false, 4, 0);
  #|  const ibo = gl.createBuffer();
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
  #|  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
  #|  gl.bindVertexArray(null);
  #|  const type = indexBytes === 2 ? gl.UNSIGNED_SHORT : gl.UNSIGNED_INT;
  #|  return { vao, vbo, ibo, ele, vertices: n, count, type };
  #|}

///|
/// Where an extrusion entry's features start and their centroids: vertex index,
/// centroid x, y for each run of vertices sharing a centroid.
extern "js" fn extrusion_runs_of(vertices : JsBuffer) -> FixedArray[Int32] =
  #|(vertices) => {
  #|  const v = new Int16Array(vertices), out = [];
  #|  for (let i = 0, n = v.length / 12; i < n; i++) {
  #|    const x = v[i * 12 + 6], y = v[i * 12 + 7];
  #|    if (i === 0 || x !== v[i * 12 - 6] || y !== v[i * 12 - 5]) out.push(i, x, y);
  #|  }
  #|  return out;
  #|}

///|
/// Sets the ground (meters) under each run of `runs` (as `extrusion_runs`
/// lists them) to the matching value of `heights`.
extern "js" fn gl_set_ground(
  gl : Gl,
  mesh : Mesh,
  runs : FixedArray[Int32],
  heights : FixedArray[Double],
) -> Unit =
  #|(c, m, runs, heights) => {
  #|  const gl = c.gl, out = new Float32Array(m.vertices);
  #|  for (let r = 0; r < heights.length; r++) {
  #|    const end = r + 1 < heights.length ? runs[(r + 1) * 3] : m.vertices;
  #|    out.fill(heights[r], runs[r * 3], end);
  #|  }
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, m.ele);
  #|  gl.bufferData(gl.ARRAY_BUFFER, out, gl.DYNAMIC_DRAW);
  #|}

///|
/// Draws an extrusion mesh depth-tested (twice when translucent: depth, then
/// color). `light`: direction, intensity, color; `heights`: zoom mix, world
/// pixels per meter, terrain exaggeration (0 without terrain).
extern "js" fn gl_draw_extrusion(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  color : FixedArray[Double],
  opacity : Double,
  light : FixedArray[Double],
  gradient : Bool,
  heights : FixedArray[Double],
  program : String,
  pass : Int32,
) -> Unit =
  #|(c, m, matrix, clip, color, opacity, light, gradient, heights, name, pass) => {
  #|  const gl = c.gl, p = c[name];
  #|  gl.useProgram(p.program);
  #|  if (p.u_height_factor) gl.uniform1f(p.u_height_factor, heights[3]);
  #|  c.place(p, matrix, clip);
  #|  gl.uniform3f(p.u_color, color[0], color[1], color[2]);
  #|  gl.uniform1f(p.u_opacity, opacity);
  #|  gl.uniform3f(p.u_lightpos, light[0], light[1], light[2]);
  #|  gl.uniform1f(p.u_lightintensity, light[3]);
  #|  gl.uniform3f(p.u_lightcolor, light[4], light[5], light[6]);
  #|  gl.uniform3f(p.u_lightpos_globe, light[7], light[8], light[9]);
  #|  gl.uniform4f(p.u_ambient, light[11], light[12], light[13], light[10]);
  #|  gl.uniform3f(p.u_sun, light[14], light[15], light[16]);
  #|  gl.uniform1f(p.u_vertical_gradient, gradient ? 1 : 0);
  #|  gl.uniform1f(p.u_t, heights[0]);
  #|  gl.uniform1f(p.u_scale, heights[1]);
  #|  gl.uniform1f(p.u_ground, heights[2]);
  #|  gl.bindVertexArray(m.vao);
  #|  gl.enable(gl.DEPTH_TEST);
  #|  gl.depthFunc(gl.LEQUAL);
  #|  // Pass 1 fills depth only; pass 2 colors each pixel once (the stencil counts).
  #|  if (pass === 1) gl.colorMask(false, false, false, false);
  #|  if (pass === 2) {
  #|    gl.enable(gl.STENCIL_TEST);
  #|    gl.stencilFunc(gl.EQUAL, 0, 0xff);
  #|    gl.stencilOp(gl.KEEP, gl.KEEP, gl.INCR);
  #|  }
  #|  c.draw(m);
  #|  gl.colorMask(true, true, true, true);
  #|  gl.disable(gl.STENCIL_TEST);
  #|  gl.disable(gl.DEPTH_TEST);
  #|}

///|
extern "js" fn gl_clear_stencil(gl : Gl) -> Unit =
  #|(c) => { c.gl.clearStencil(0); c.gl.clear(c.gl.STENCIL_BUFFER_BIT); }
