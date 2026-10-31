///|
/// Draws packed tile layers with WebGL2. Colors are straight RGBA in [0, 1];
/// sizes are in device pixels unless noted.
pub struct Renderer {
  priv gl : Gl
}

///|
/// None if the canvas cannot provide a WebGL2 context.
pub fn Renderer::new(canvas : Canvas) -> Renderer? {
  let gl = create_gl(canvas)
  if is_null(gl) {
    None
  } else {
    Some({ gl, })
  }
}

///|
pub fn Renderer::set_viewport(
  self : Renderer,
  width : Int32,
  height : Int32,
) -> Unit {
  gl_viewport(self.gl, width, height)
}

///|
/// Clears the frame to an opaque color and drops any scissor.
pub fn Renderer::clear(
  self : Renderer,
  r : Double,
  g : Double,
  b : Double,
) -> Unit {
  gl_clear(self.gl, r, g, b)
}

///|
/// Restricts drawing to a rectangle, in device pixels from the bottom left.
pub fn Renderer::scissor(
  self : Renderer,
  x : Int32,
  y : Int32,
  w : Int32,
  h : Int32,
) -> Unit {
  gl_scissor(self.gl, x, y, w, h)
}

///|
pub fn Renderer::no_scissor(self : Renderer) -> Unit {
  gl_no_scissor(self.gl)
}

///|
/// Uploads a packed fill (`line` false) or line layer; `count` is its index
/// count and `index_bytes` 2 or 4.
pub fn Renderer::upload(
  self : Renderer,
  line : Bool,
  vertices : JsBuffer,
  indices : JsBuffer,
  count : Int32,
  index_bytes : Int32,
) -> Mesh {
  gl_upload(self.gl, line, vertices, indices, count, index_bytes)
}

///|
pub fn Renderer::release(self : Renderer, mesh : Mesh) -> Unit {
  gl_release(self.gl, mesh)
}

///|
/// GPU bytes held by a mesh.
pub fn Mesh::byte_size(self : Mesh) -> Int32 {
  mesh_bytes(self)
}

///|
pub fn Renderer::draw_fill(
  self : Renderer,
  mesh : Mesh,
  t : @core.TileTransform,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> Unit {
  gl_draw_fill(
    self.gl,
    mesh,
    t.scale_x,
    t.scale_y,
    t.translate_x,
    t.translate_y,
    r,
    g,
    b,
    a,
  )
}

///|
/// Draws a line layer `width` device pixels wide, plus a pixel of antialiasing.
pub fn Renderer::draw_line(
  self : Renderer,
  mesh : Mesh,
  t : @core.TileTransform,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
  width : Double,
) -> Unit {
  gl_draw_line(
    self.gl,
    mesh,
    t.scale_x,
    t.scale_y,
    t.translate_x,
    t.translate_y,
    r,
    g,
    b,
    a,
    width / 2.0 + 0.5,
  )
}
