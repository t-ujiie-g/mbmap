///|
/// Shadows from now on: `mode` 0 none, 1 through each draw's tile light matrix,
/// 2 through `sphere` (unit sphere to the light's clip space); `intensity` how
/// dark they are, `texel` the depth one texel spans (`@core.ShadowView`).
pub fn Renderer::set_shadow(
  self : Renderer,
  mode : Int32,
  sphere : @core.Mat4,
  intensity : Double,
  texel : Double,
) -> Unit {
  gl_set_shadow(self.gl, mode, sphere.m, intensity, texel)
}

///|
extern "js" fn gl_set_shadow(
  gl : Gl,
  mode : Int32,
  sphere : FixedArray[Double],
  intensity : Double,
  texel : Double,
) -> Unit =
  #|(c, mode, sphere, intensity, texel) => {
  #|  c.shadow.mode = mode;
  #|  c.shadow.globe.set(sphere);
  #|  c.shadow.k = [intensity, texel];
  #|}

///|
/// Starts drawing casters' depth into the shadow map (made the first time),
/// until `end_shadow_map`.
pub fn Renderer::begin_shadow_map(self : Renderer) -> Unit {
  gl_begin_shadow_map(self.gl)
}

///|
extern "js" fn gl_begin_shadow_map(gl : Gl) -> Unit =
  #|(c) => {
  #|  const gl = c.gl, S = c.shadowSize;
  #|  c.shadowSaved = { fbo: gl.getParameter(gl.FRAMEBUFFER_BINDING), viewport: gl.getParameter(gl.VIEWPORT) };
  #|  if (!c.shadowMap) {
  #|    const tex = gl.createTexture();
  #|    gl.activeTexture(gl.TEXTURE7);
  #|    gl.bindTexture(gl.TEXTURE_2D, tex);
  #|    gl.texStorage2D(gl.TEXTURE_2D, 1, gl.DEPTH_COMPONENT24, S, S);
  #|    for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.LINEAR], [gl.TEXTURE_MAG_FILTER, gl.LINEAR], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE],
  #|      [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE], [gl.TEXTURE_COMPARE_MODE, gl.COMPARE_REF_TO_TEXTURE], [gl.TEXTURE_COMPARE_FUNC, gl.LEQUAL]])
  #|      gl.texParameteri(gl.TEXTURE_2D, k, v);
  #|    const fbo = gl.createFramebuffer();
  #|    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
  #|    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, tex, 0);
  #|    c.shadowMap = { tex, fbo };
  #|  }
  #|  // Unbound while drawn into, so no program samples it then (a feedback loop).
  #|  gl.activeTexture(gl.TEXTURE7);
  #|  gl.bindTexture(gl.TEXTURE_2D, null);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, c.shadowMap.fbo);
  #|  gl.drawBuffers([gl.NONE]);
  #|  gl.viewport(0, 0, S, S);
  #|  gl.depthMask(true);
  #|  gl.clearDepth(1);
  #|  gl.clear(gl.DEPTH_BUFFER_BIT);
  #|  gl.disable(gl.BLEND);
  #|  gl.enable(gl.POLYGON_OFFSET_FILL);
  #|  gl.polygonOffset(1, 2);
  #|}

///|
/// Ends the shadow map's drawing and binds it for the frame's draws.
pub fn Renderer::end_shadow_map(self : Renderer) -> Unit {
  gl_end_shadow_map(self.gl)
}

///|
extern "js" fn gl_end_shadow_map(gl : Gl) -> Unit =
  #|(c) => {
  #|  const gl = c.gl, v = c.shadowSaved.viewport;
  #|  gl.disable(gl.POLYGON_OFFSET_FILL);
  #|  gl.enable(gl.BLEND);
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, c.shadowSaved.fbo);
  #|  gl.viewport(v[0], v[1], v[2], v[3]);
  #|  gl.activeTexture(gl.TEXTURE7);
  #|  gl.bindTexture(gl.TEXTURE_2D, c.shadowMap.tex);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|}

///|
/// Darkens the ground of a tile (its quad, or on the globe its mesh) where it
/// lies in shadow, by `sun` (the share of the ground's light the sun gives);
/// `light` is the tile's light matrix.
pub fn Renderer::draw_ground_shadow(
  self : Renderer,
  at : Placement,
  light : @core.Mat4,
  sun : Double,
) -> Unit {
  self.use_globe(at.globe)
  gl_draw_ground_shadow(self.gl, at.matrix.m, at.clip, light.m, sun)
}

///|
extern "js" fn gl_draw_ground_shadow(
  gl : Gl,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  light : FixedArray[Double],
  sun : Double,
) -> Unit =
  #|(c, matrix, clip, light, sun) => {
  #|  const gl = c.gl, p = c.groundShadow;
  #|  gl.useProgram(p.program);
  #|  c.place(p, matrix, clip);
  #|  c.shadowUniforms(p, light, false);
  #|  gl.uniform1f(p.u_ground, sun);
  #|  c.drawTile();
  #|  gl.bindVertexArray(null);
  #|}
