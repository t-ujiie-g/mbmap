///|
/// Uploads the pattern atlas (straight RGBA, premultiplied by the upload as
/// MapLibre's textures are) as texture unit 0's `c.patterns`, filtered linearly.
extern "js" fn gl_pattern_atlas(
  gl : Gl,
  data : FixedArray[Byte],
  width : Int32,
  height : Int32,
) -> Unit =
  #|(c, data, w, h) => {
  #|  const gl = c.gl;
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  if (!c.patterns) {
  #|    c.patterns = gl.createTexture();
  #|    gl.bindTexture(gl.TEXTURE_2D, c.patterns);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  #|  } else gl.bindTexture(gl.TEXTURE_2D, c.patterns);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
  #|  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
  #|  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  #|  c.patternSize = [w, h];
  #|}

///|
/// Sets program `name`'s pattern uniforms from `u`: size (2), pixel (4),
/// units, atlas rectangle (4), sdf; binds the atlas.
extern "js" fn gl_set_pattern(
  gl : Gl,
  name : String,
  u : FixedArray[Double],
) -> Unit =
  #|(c, name, u) => {
  #|  const gl = c.gl, p = c[name];
  #|  gl.useProgram(p.program);
  #|  gl.uniform2f(p.u_size, u[0], u[1]);
  #|  gl.uniform4f(p.u_pixel, u[2], u[3], u[4], u[5]);
  #|  gl.uniform1f(p.u_units, u[6]);
  #|  gl.uniform4f(p.u_pattern, u[7], u[8], u[9], u[10]);
  #|  gl.uniform2f(p.u_texsize, c.patternSize[0], c.patternSize[1]);
  #|  gl.uniform1i(p.u_sdf, u[11]);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, c.patterns);
  #|  gl.uniform1i(p.u_image, 0);
  #|}

///|
/// Draws a tile quad with the background pattern (uniforms set), `opacity`
/// and, for an SDF pattern, `color` (premultiplied).
extern "js" fn gl_draw_background_pattern(
  gl : Gl,
  matrix : FixedArray[Double],
  opacity : Double,
  color : FixedArray[Double],
) -> Unit =
  #|(c, matrix, opacity, color) => {
  #|  const gl = c.gl, p = c.backgroundPattern;
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform1f(p.u_opacity, opacity);
  #|  gl.uniform4f(p.u_color, color[0], color[1], color[2], color[3]);
  #|  gl.bindVertexArray(c.quad);
  #|  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  #|  gl.bindVertexArray(null);
  #|}
