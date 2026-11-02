///|
/// The largest side an offscreen frame may have on this GPU: its render
/// buffers, viewport and the label depth texture must all hold it.
extern "js" fn gl_max_side(gl : Gl) -> Int32 =
  #|(c) => {
  #|  const gl = c.gl, v = gl.getParameter(gl.MAX_VIEWPORT_DIMS);
  #|  return Math.min(gl.getParameter(gl.MAX_RENDERBUFFER_SIZE), gl.getParameter(gl.MAX_TEXTURE_SIZE), v[0], v[1]);
  #|}

///|
extern "js" fn gl_offscreen_begin(
  gl : Gl,
  width : Int32,
  height : Int32,
) -> Unit =
  #|(c, w, h) => {
  #|  const gl = c.gl, fb = gl.createFramebuffer();
  #|  const color = gl.createRenderbuffer(), depth = gl.createRenderbuffer();
  #|  gl.bindRenderbuffer(gl.RENDERBUFFER, color);
  #|  gl.renderbufferStorage(gl.RENDERBUFFER, gl.RGBA8, w, h);
  #|  gl.bindRenderbuffer(gl.RENDERBUFFER, depth);
  #|  gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, w, h);
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  #|  gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, color);
  #|  gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depth);
  #|  c.out = fb;
  #|  c.offscreen = { fb, color, depth, w, h };
  #|  gl.viewport(0, 0, w, h);
  #|  c.px = [2 / w, 2 / h];
  #|  c.size = [w, h];
  #|}

///|
/// The offscreen frame's pixels, top row first, opaque RGBA, and back to the
/// canvas.
extern "js" fn gl_offscreen_end(gl : Gl) -> JsBuffer =
  #|(c) => {
  #|  const gl = c.gl, o = c.offscreen, row = o.w * 4;
  #|  const raw = new Uint8Array(row * o.h), out = new Uint8ClampedArray(row * o.h);
  #|  gl.readPixels(0, 0, o.w, o.h, gl.RGBA, gl.UNSIGNED_BYTE, raw);
  #|  for (let y = 0; y < o.h; y++) out.set(raw.subarray((o.h - 1 - y) * row, (o.h - y) * row), y * row);
  #|  for (let i = 3; i < out.length; i += 4) out[i] = 255;
  #|  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  #|  gl.deleteFramebuffer(o.fb);
  #|  gl.deleteRenderbuffer(o.color);
  #|  gl.deleteRenderbuffer(o.depth);
  #|  c.out = c.offscreen = null;
  #|  return out;
  #|}

///|
/// The largest frame side `begin_offscreen` takes.
pub fn Renderer::max_side(self : Renderer) -> Int32 {
  gl_max_side(self.gl)
}

///|
/// Draws into a `width` x `height` offscreen frame from now on, until
/// `end_offscreen` gives its pixels.
pub fn Renderer::begin_offscreen(
  self : Renderer,
  width : Int32,
  height : Int32,
) -> Unit {
  gl_offscreen_begin(self.gl, width, height)
}

///|
/// The offscreen frame's pixels (a Uint8ClampedArray, top row first, RGBA),
/// and drawing back into the canvas.
pub fn Renderer::end_offscreen(self : Renderer) -> JsBuffer {
  gl_offscreen_end(self.gl)
}
