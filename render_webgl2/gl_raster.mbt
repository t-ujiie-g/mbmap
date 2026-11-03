///|
/// A tile's slopes as a two-channel byte texture, filtered linearly.
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
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RG8, size, size, 0, gl.RG, gl.UNSIGNED_BYTE, new Uint8Array(slopes));
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|  return { texture, size, bytes: size * size * 2 };
  #|}

///|
extern "js" fn gl_slopes_side(
  gl : Gl,
  mesh : Mesh,
  side : Int32,
  slopes : Bytes,
) -> Unit =
  #|(c, m, side, slopes) => {
  #|  const gl = c.gl, n = m.size;
  #|  gl.bindTexture(gl.TEXTURE_2D, m.texture);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  #|  const [x, y, w, h] = [[0, 0, n, 1], [0, n - 1, n, 1], [0, 0, 1, n], [n - 1, 0, 1, n]][side];
  #|  gl.texSubImage2D(gl.TEXTURE_2D, 0, x, y, w, h, gl.RG, gl.UNSIGNED_BYTE, slopes);
  #|}

///|
/// `lat_light` is the tile's north and south latitude, then the light's azimuth
/// and exaggeration; colors are straight RGBA.
extern "js" fn gl_draw_hillshade(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  lat_light : FixedArray[Double],
  shadow : FixedArray[Double],
  highlight : FixedArray[Double],
  accent : FixedArray[Double],
) -> Unit =
  #|(c, m, matrix, clip, ll, shadow, highlight, accent) => {
  #|  const gl = c.gl, p = c.hillshade;
  #|  const pre = (loc, v) => gl.uniform4f(loc, v[0] * v[3], v[1] * v[3], v[2] * v[3], v[3]);
  #|  gl.useProgram(p.program);
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform2f(p.u_lat, ll[0], ll[1]);
  #|  gl.uniform2f(p.u_light, ll[2], ll[3]);
  #|  pre(p.u_shadow, shadow);
  #|  pre(p.u_highlight, highlight);
  #|  pre(p.u_accent, accent);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, m.texture);
  #|  gl.uniform1i(p.u_image, 0);
  #|  gl.bindVertexArray(c.quad);
  #|  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
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
  #|  const bytes = image.width * image.height * 4 * 4 / 3;
  #|  image.close?.();
  #|  return { texture, bytes };
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
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform1f(p.u_opacity, k[0]);
  #|  gl.uniform2f(p.u_bright, k[1], k[2]);
  #|  gl.uniform1f(p.u_saturation, k[3]);
  #|  gl.uniform1f(p.u_contrast, k[4]);
  #|  gl.uniform3f(p.u_spin, k[5], k[6], k[7]);
  #|  const q = m.quad, e = 4096;
  #|  if (q) gl.uniform4f(p.u_top, q[0], q[1], q[2], q[3]), gl.uniform4f(p.u_bottom, q[6], q[7], q[4], q[5]), gl.uniform3f(p.u_warp, q[8], q[9], q[10]);
  #|  else gl.uniform4f(p.u_top, 0, 0, e, 0), gl.uniform4f(p.u_bottom, 0, e, e, e), gl.uniform3f(p.u_warp, 0, 0, 1);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, m.texture);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, nearest ? gl.NEAREST : gl.LINEAR);
  #|  // Pictures have no mipmaps: MapLibre then minifies linearly, even when `nearest`.
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, q ? gl.LINEAR : nearest ? gl.NEAREST : gl.LINEAR_MIPMAP_NEAREST);
  #|  gl.uniform1i(p.u_image, 0);
  #|  if (q && q[11]) {
  #|    gl.bindVertexArray(c.imageGrid);
  #|    gl.drawElements(gl.TRIANGLES, 16 * 16 * 6, gl.UNSIGNED_SHORT, 0);
  #|  } else {
  #|    gl.bindVertexArray(c.quad);
  #|    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
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
  #|  m.bytes = w * h * 4;
  #|  return m;
  #|}

///|
/// Gives a picture's mesh its corners in tile units (top left, top right, bottom
/// right, bottom left), its warp and whether it is drawn over a 16 x 16 grid.
extern "js" fn gl_set_quad(mesh : Mesh, quad : FixedArray[Double]) -> Unit =
  #|(m, q) => { m.quad = q.slice(3, 15); }
