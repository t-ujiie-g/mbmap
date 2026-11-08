///|
/// A tile's slopes (with their border) as a two-channel byte texture.
extern "js" fn gl_upload_slopes(
  gl : Gl,
  slopes : JsBuffer,
  size : Int32,
) -> Mesh =
  #|(c, slopes, size) => {
  #|  const gl = c.gl;
  #|  const texture = gl.createTexture();
  #|  gl.bindTexture(gl.TEXTURE_2D, texture);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RG8, size + 2, size + 2, 0, gl.RG, gl.UNSIGNED_BYTE, new Uint8Array(slopes));
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|  return { texture, size };
  #|}

///|
extern "js" fn gl_slopes_side(
  gl : Gl,
  mesh : Mesh,
  side : Int32,
  slopes : Bytes,
  border : Bool,
) -> Unit =
  #|(c, m, side, slopes, border) => {
  #|  const gl = c.gl, n = m.size, near = border ? 0 : 1, far = border ? n + 1 : n;
  #|  gl.bindTexture(gl.TEXTURE_2D, m.texture);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  #|  const [x, y, w, h] = [[1, near, n, 1], [1, far, n, 1], [near, 1, 1, n], [far, 1, 1, n]][side];
  #|  gl.texSubImage2D(gl.TEXTURE_2D, 0, x, y, w, h, gl.RG, gl.UNSIGNED_BYTE, slopes);
  #|}

///|
/// `params`: the tile's north and south latitude, exaggeration, method, number
/// of lights and whether to sample the nearest pixel; `angles` and `colors` as
/// `Renderer::draw_hillshade` takes them.
extern "js" fn gl_draw_hillshade(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  params : FixedArray[Double],
  angles : FixedArray[Double],
  colors : FixedArray[Double],
  accent : FixedArray[Double],
) -> Unit =
  #|(c, m, matrix, clip, k, angles, colors, accent) => {
  #|  const gl = c.gl, p = c.hillshade, n = k[4];
  #|  const pre = (v, i) => [v[i] * v[i + 3], v[i + 1] * v[i + 3], v[i + 2] * v[i + 3], v[i + 3]];
  #|  const lights = (at) => new Float32Array(Array.from({ length: n }, (_, i) => pre(colors, (i * 2 + at) * 4)).flat());
  #|  gl.useProgram(p.program);
  #|  c.place(p, matrix, clip);
  #|  gl.uniform2f(p.u_lat, k[0], k[1]);
  #|  gl.uniform1f(p.u_exaggeration, k[2]);
  #|  gl.uniform1i(p.u_method, k[3]);
  #|  gl.uniform1i(p.u_count, n);
  #|  gl.uniform1fv(p.u_azimuths, angles.filter((_, i) => i % 2 == 0));
  #|  gl.uniform1fv(p.u_altitudes, angles.filter((_, i) => i % 2 == 1));
  #|  gl.uniform4fv(p.u_shadows, lights(0));
  #|  gl.uniform4fv(p.u_highlights, lights(1));
  #|  gl.uniform4fv(p.u_accent, pre(accent, 0));
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, m.texture);
  #|  const f = k[5] ? gl.NEAREST : gl.LINEAR;
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, f);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, f);
  #|  gl.uniform1i(p.u_image, 0);
  #|  c.drawTile();
  #|}

///|
/// A DEM tile's `heights` packed into RGB by `unpack` (MapLibre's `packDEMData`)
/// with MapLibre's 2-pixel border repeating the edges, kept on the mesh.
extern "js" fn gl_relief_heights(
  gl : Gl,
  mesh : Mesh,
  heights : JsBuffer,
  size : Int32,
  unpack : FixedArray[Double],
) -> Unit =
  #|(c, m, heights, size, u) => {
  #|  const gl = c.gl, stride = size + 4, data = new Uint8Array(stride * stride * 4);
  #|  for (let y = 0; y < stride; y++) for (let x = 0; x < stride; x++) {
  #|    const sx = Math.min(size - 1, Math.max(0, x - 2)), sy = Math.min(size - 1, Math.max(0, y - 2));
  #|    c.packDem(heights[sy * size + sx], u, data, (y * stride + x) * 4);
  #|  }
  #|  m.relief = gl.createTexture();
  #|  m.reliefSize = stride;
  #|  gl.bindTexture(gl.TEXTURE_2D, m.relief);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, stride, stride, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|}

///|
/// Copies into the border of a mesh's `gl_relief_heights` the pixels of the
/// same-size tile (`dx`, `dy`) beside it, from its `heights` (MapLibre's
/// `backfillBorder`).
extern "js" fn gl_relief_border(
  gl : Gl,
  mesh : Mesh,
  heights : JsBuffer,
  size : Int32,
  unpack : FixedArray[Double],
  dx : Int32,
  dy : Int32,
) -> Unit =
  #|(c, m, heights, size, u, dx, dy) => {
  #|  const gl = c.gl, range = (d) => (d < 0 ? [-2, 0] : d > 0 ? [size, size + 2] : [0, size]);
  #|  const [x0, x1] = range(dx), [y0, y1] = range(dy), w = x1 - x0, h = y1 - y0, data = new Uint8Array(w * h * 4);
  #|  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++)
  #|    c.packDem(heights[(y - dy * size) * size + x - dx * size], u, data, ((y - y0) * w + x - x0) * 4);
  #|  gl.bindTexture(gl.TEXTURE_2D, m.relief);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
  #|  gl.texSubImage2D(gl.TEXTURE_2D, 0, x0 + 2, y0 + 2, w, h, gl.RGBA, gl.UNSIGNED_BYTE, data);
  #|}

///|
extern "js" fn gl_has_relief(mesh : Mesh) -> Bool =
  #|(m) => m.relief != null

///|
/// Adds to `g`, a color relief's colors (`gl_upload_gradient`), its elevation
/// `stops` packed by `unpack` as `gl_relief_heights` packs.
extern "js" fn gl_relief_ramp(
  gl : Gl,
  g : Gradient,
  stops : FixedArray[Double],
  unpack : FixedArray[Double],
) -> Unit =
  #|(c, g, stops, u) => {
  #|  const gl = c.gl, n = stops.length, data = new Uint8Array(n * 4);
  #|  stops.forEach((v, i) => c.packDem(v, u, data, i * 4));
  #|  const elevations = gl.createTexture();
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, elevations);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, n, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  #|  g.elevations = elevations;
  #|  g.size = n;
  #|}

///|
/// `k` is the opacity and whether to sample the nearest DEM pixel.
extern "js" fn gl_draw_relief(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  ramp : Gradient,
  unpack : FixedArray[Double],
  k : FixedArray[Double],
) -> Unit =
  #|(c, m, matrix, clip, g, u, k) => {
  #|  const gl = c.gl, p = c.colorRelief, f = k[1] ? gl.NEAREST : gl.LINEAR;
  #|  gl.useProgram(p.program);
  #|  c.place(p, matrix, clip);
  #|  gl.uniform2f(p.u_dimension, m.reliefSize, m.reliefSize);
  #|  gl.uniform4f(p.u_unpack, u[0], u[1], u[2], u[3]);
  #|  gl.uniform1i(p.u_color_ramp_size, g.size);
  #|  gl.uniform1f(p.u_opacity, k[0]);
  #|  gl.activeTexture(gl.TEXTURE1);
  #|  gl.bindTexture(gl.TEXTURE_2D, g.elevations);
  #|  gl.uniform1i(p.u_elevation_stops, 1);
  #|  gl.activeTexture(gl.TEXTURE2);
  #|  gl.bindTexture(gl.TEXTURE_2D, g.texture);
  #|  gl.uniform1i(p.u_color_stops, 2);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, m.relief);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, f);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, f);
  #|  gl.uniform1i(p.u_image, 0);
  #|  c.drawTile();
  #|}

///|
/// A raster tile's image (an ImageBitmap) as a mipmapped texture.
extern "js" fn gl_upload_raster(gl : Gl, image : JsBuffer) -> Mesh =
  #|(c, image) => {
  #|  const gl = c.gl;
  #|  const texture = gl.createTexture();
  #|  gl.bindTexture(gl.TEXTURE_2D, texture);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
  #|  gl.generateMipmap(gl.TEXTURE_2D);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|  image.close?.();
  #|  return { texture };
  #|}

///|
/// `colors` is opacity, brightness min and max, saturation and contrast
/// factors and the hue spin weights (MapLibre's raster uniforms).
extern "js" fn gl_draw_raster(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  colors : FixedArray[Double],
  nearest : Bool,
) -> Unit =
  #|(c, m, matrix, clip, k, nearest) => {
  #|  const gl = c.gl, p = c.raster;
  #|  gl.useProgram(p.program);
  #|  c.place(p, matrix, clip);
  #|  gl.uniform1f(p.u_opacity, k[0]);
  #|  gl.uniform2f(p.u_bright, k[1], k[2]);
  #|  gl.uniform1f(p.u_saturation, k[3]);
  #|  gl.uniform1f(p.u_contrast, k[4]);
  #|  gl.uniform3f(p.u_spin, k[5], k[6], k[7]);
  #|  const q = m.quad, e = c.extent;
  #|  if (q) gl.uniform4f(p.u_top, q[0], q[1], q[2], q[3]), gl.uniform4f(p.u_bottom, q[6], q[7], q[4], q[5]), gl.uniform3f(p.u_warp, q[8], q[9], q[10]);
  #|  else gl.uniform4f(p.u_top, 0, 0, e, 0), gl.uniform4f(p.u_bottom, 0, e, e, e), gl.uniform3f(p.u_warp, 0, 0, 1);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, m.texture);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, nearest ? gl.NEAREST : gl.LINEAR);
  #|  // Pictures have no mipmaps: MapLibre then minifies linearly, even when `nearest`.
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, q ? gl.LINEAR : nearest ? gl.NEAREST : gl.LINEAR_MIPMAP_NEAREST);
  #|  // MapLibre filters mipmapped tiles anisotropically above 20° of pitch (and leaves it on).
  #|  if (!q && c.pitch > 20) {
  #|    c.aniso ??= gl.getExtension("EXT_texture_filter_anisotropic") ?? false;
  #|    if (c.aniso) gl.texParameterf(gl.TEXTURE_2D, c.aniso.TEXTURE_MAX_ANISOTROPY_EXT, gl.getParameter(c.aniso.MAX_TEXTURE_MAX_ANISOTROPY_EXT));
  #|  }
  #|  gl.uniform1i(p.u_image, 0);
  #|  if (q && q[11]) {
  #|    gl.bindVertexArray(c.imageGrid);
  #|    gl.drawElements(gl.TRIANGLES, 16 * 16 * 6, gl.UNSIGNED_SHORT, 0);
  #|  } else {
  #|    c.drawTile();
  #|  }
  #|}

///|
/// A picture as a texture without mipmaps, premultiplied as MapLibre uploads it,
/// into `old`'s texture if given (else a new mesh); `old` while a video has no
/// frame or a canvas no pixels.
extern "js" fn gl_upload_picture(
  gl : Gl,
  picture : Picture,
  old : Mesh,
) -> Mesh =
  #|(c, image, old) => {
  #|  const w = image.videoWidth ?? image.width, h = image.videoHeight ?? image.height;
  #|  if ((image.readyState ?? 4) < 2 || !(w > 0 && h > 0)) return old;
  #|  const gl = c.gl;
  #|  const texture = old?.texture ?? gl.createTexture();
  #|  gl.bindTexture(gl.TEXTURE_2D, texture);
  #|  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
  #|  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|  const m = old ?? { texture, quad: null };
  #|  return m;
  #|}

///|
/// Gives a picture's mesh its corners in tile units (top left, top right, bottom
/// right, bottom left), its warp and whether it is drawn over a 16 x 16 grid.
extern "js" fn gl_set_quad(mesh : Mesh, quad : FixedArray[Double]) -> Unit =
  #|(m, q) => { m.quad = q.slice(3, 15); }
