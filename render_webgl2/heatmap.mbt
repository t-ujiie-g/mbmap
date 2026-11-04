///|
/// Binds the density texture (the viewport times `scale`; RGBA16F as MapLibre's,
/// RGBA8 without `EXT_color_buffer_float`), cleared, with additive blending
/// until `gl_heatmap_end`.
extern "js" fn gl_heatmap_begin(gl : Gl, scale : Double) -> Unit =
  #|(c, scale) => {
  #|  const gl = c.gl, vp = gl.getParameter(gl.VIEWPORT);
  #|  const w = Math.max(1, Math.floor(vp[2] * scale)), h = Math.max(1, Math.floor(vp[3] * scale));
  #|  c.heatFrom = { fb: gl.getParameter(gl.FRAMEBUFFER_BINDING), vp };
  #|  let t = c.heat;
  #|  if (!t || t.w !== w || t.h !== h) {
  #|    if (t) { gl.deleteFramebuffer(t.fb); gl.deleteTexture(t.texture); }
  #|    const make = (format) => {
  #|      const texture = gl.createTexture();
  #|      gl.bindTexture(gl.TEXTURE_2D, texture);
  #|      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  #|      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  #|      gl.texStorage2D(gl.TEXTURE_2D, 1, format, w, h);
  #|      const fb = gl.createFramebuffer();
  #|      gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  #|      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
  #|      if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE) return { fb, texture, w, h };
  #|      gl.deleteFramebuffer(fb);
  #|      gl.deleteTexture(texture);
  #|      return null;
  #|    };
  #|    c.heatFloat ??= gl.getExtension("EXT_color_buffer_float") != null;
  #|    t = c.heat = (c.heatFloat && make(gl.RGBA16F)) || make(gl.RGBA8);
  #|  }
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, t.fb);
  #|  gl.viewport(0, 0, w, h);
  #|  gl.clearColor(0, 0, 0, 0);
  #|  gl.clear(gl.COLOR_BUFFER_BIT);
  #|  gl.blendFunc(gl.ONE, gl.ONE);
  #|}

///|
extern "js" fn gl_draw_heatmap(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  extrude : Double,
  intensity : Double,
) -> Unit =
  #|(c, m, matrix, extrude, intensity) => {
  #|  const gl = c.gl, p = c.heatmap;
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform1f(p.u_extrude, extrude);
  #|  gl.uniform1f(p.u_intensity, intensity);
  #|  gl.drawElements(gl.TRIANGLES, m.rangeCount ?? m.count, m.type, m.rangeOffset ?? 0);
  #|}

///|
/// Back into the framebuffer and viewport `gl_heatmap_begin` found, and draws
/// the density there through `ramp` (texture unit 1) times `opacity`.
extern "js" fn gl_heatmap_end(
  gl : Gl,
  ramp : Gradient,
  opacity : Double,
) -> Unit =
  #|(c, ramp, opacity) => {
  #|  const gl = c.gl, p = c.heatmapTexture, from = c.heatFrom, vp = from.vp;
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, from.fb);
  #|  gl.viewport(vp[0], vp[1], vp[2], vp[3]);
  #|  gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  #|  if (opacity <= 0) return;
  #|  gl.useProgram(p.program);
  #|  gl.activeTexture(gl.TEXTURE1);
  #|  gl.bindTexture(gl.TEXTURE_2D, ramp.texture);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, c.heat.texture);
  #|  gl.uniform1i(p.u_image, 0);
  #|  gl.uniform1i(p.u_ramp, 1);
  #|  gl.uniform1f(p.u_opacity, opacity);
  #|  gl.bindVertexArray(c.empty);
  #|  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  #|}

///|
/// Starts a heatmap layer (MapLibre's offscreen pass): its kernels go into a
/// density texture `scale` times the viewport's size until `end_heatmap`.
pub fn Renderer::begin_heatmap(self : Renderer, scale : Double) -> Unit {
  gl_heatmap_begin(self.gl, scale)
}

///|
/// Adds a heatmap mesh's kernels (the circle layout) to the density: weight and
/// radius (CSS px) from `slots`, `px` device pixels per CSS pixel at the center.
pub fn Renderer::draw_heatmap(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
  intensity : Double,
  px : Double,
) -> Unit {
  self.bind("heatmap", mesh, slots, 3)
  gl_draw_heatmap(
    self.gl,
    mesh,
    at.matrix.m,
    at.units_per_pixel * px,
    intensity,
  )
}

///|
/// Ends a heatmap layer: its density colored through `ramp` (`upload_gradient`
/// of a 256-pixel `color_ramp` over density) times `opacity`.
pub fn Renderer::end_heatmap(
  self : Renderer,
  ramp : Gradient,
  opacity : Double,
) -> Unit {
  gl_heatmap_end(self.gl, ramp, opacity)
}
