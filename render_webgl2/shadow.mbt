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
/// until `end_shadow_map`; into its corner `size` texels across if given.
pub fn Renderer::begin_shadow_map(self : Renderer, size? : Int32) -> Unit {
  gl_begin_shadow_map(self.gl, size.unwrap_or(@core.SHADOW_MAP_SIZE))
}

///|
extern "js" fn gl_begin_shadow_map(gl : Gl, size : Int32) -> Unit =
  #|(c, size) => {
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
  #|  gl.viewport(0, 0, size, size);
  #|  gl.depthMask(true);
  #|  gl.clearDepth(1);
  #|  gl.enable(gl.SCISSOR_TEST);
  #|  gl.scissor(0, 0, size, size);
  #|  gl.clear(gl.DEPTH_BUFFER_BIT);
  #|  gl.disable(gl.SCISSOR_TEST);
  #|  gl.disable(gl.BLEND);
  #|  // Receivers compare against a little more depth; a ray reads it as it is.
  #|  if (size === S) gl.enable(gl.POLYGON_OFFSET_FILL);
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

///|
/// The depth (0 to 1) at texel (x, y) of the shadow map, read back.
pub fn Renderer::shadow_depth_at(
  self : Renderer,
  x : Int32,
  y : Int32,
) -> Double {
  gl_shadow_depth_at(self.gl, x, y)
}

///|
extern "js" fn gl_shadow_depth_at(gl : Gl, x : Int32, y : Int32) -> Double =
  #|(c, x, y) => {
  #|  const gl = c.gl;
  #|  if (!c.depthRead) {
  #|    // One point writing the texel's 24 bits of depth into RGB.
  #|    const shader = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, "#version 300 es\n" + src); gl.compileShader(s); return s; };
  #|    const p = gl.createProgram();
  #|    gl.attachShader(p, shader(gl.VERTEX_SHADER, "void main() { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); gl_PointSize = 1.0; }"));
  #|    gl.attachShader(p, shader(gl.FRAGMENT_SHADER, "precision highp float; uniform highp sampler2D u_depth; uniform ivec2 u_at; out vec4 o;" +
  #|      "void main() { float v = min(floor(texelFetch(u_depth, u_at, 0).r * 16777215.0 + 0.5), 16777215.0);" +
  #|      "  o = vec4(floor(v / 65536.0), mod(floor(v / 256.0), 256.0), mod(v, 256.0), 255.0) / 255.0; }"));
  #|    gl.linkProgram(p);
  #|    const fbo = gl.createFramebuffer(), rb = gl.createRenderbuffer();
  #|    gl.bindRenderbuffer(gl.RENDERBUFFER, rb);
  #|    gl.renderbufferStorage(gl.RENDERBUFFER, gl.RGBA8, 1, 1);
  #|    const saved = gl.getParameter(gl.FRAMEBUFFER_BINDING);
  #|    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
  #|    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, rb);
  #|    gl.bindFramebuffer(gl.FRAMEBUFFER, saved);
  #|    c.depthRead = { p, fbo, depth: gl.getUniformLocation(p, "u_depth"), at: gl.getUniformLocation(p, "u_at") };
  #|  }
  #|  const r = c.depthRead, tex = c.shadowMap.tex, px = new Uint8Array(4);
  #|  const fbo = gl.getParameter(gl.FRAMEBUFFER_BINDING), v = gl.getParameter(gl.VIEWPORT);
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, r.fbo);
  #|  gl.viewport(0, 0, 1, 1);
  #|  gl.useProgram(r.p);
  #|  gl.activeTexture(gl.TEXTURE7);
  #|  gl.bindTexture(gl.TEXTURE_2D, tex);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_COMPARE_MODE, gl.NONE);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  #|  gl.uniform1i(r.depth, 7);
  #|  gl.uniform2i(r.at, x, y);
  #|  gl.disable(gl.BLEND);
  #|  gl.bindVertexArray(null);
  #|  gl.drawArrays(gl.POINTS, 0, 1);
  #|  gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_COMPARE_MODE, gl.COMPARE_REF_TO_TEXTURE);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.enable(gl.BLEND);
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
  #|  gl.viewport(v[0], v[1], v[2], v[3]);
  #|  return (px[0] * 65536 + px[1] * 256 + px[2]) / 16777215;
  #|}
