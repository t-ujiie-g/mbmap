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
/// Clears the frame to an opaque color.
pub fn Renderer::clear(
  self : Renderer,
  r : Double,
  g : Double,
  b : Double,
) -> Unit {
  gl_clear(self.gl, r, g, b)
}

///|
/// Uploads a packed layer; `extruded` is true for the line vertex layout
/// (lines and circles), false for fills. `count` is its index count and
/// `index_bytes` 2 or 4.
pub fn Renderer::upload(
  self : Renderer,
  extruded : Bool,
  vertices : JsBuffer,
  indices : JsBuffer,
  count : Int32,
  index_bytes : Int32,
) -> Mesh {
  gl_upload(self.gl, extruded, vertices, indices, count, index_bytes)
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
/// Where a mesh is drawn: `matrix` maps tile units to clip space,
/// `units_per_pixel` holds at `center_depth` (the center's clip w), only the part
/// within `clip` (min x, min y, max x, max y in tile units) shows, and
/// `latitudes` are the tile's north and south edges in degrees.
pub(all) struct Placement {
  matrix : @core.Mat4
  units_per_pixel : Double
  center_depth : Double
  clip : FixedArray[Double]
  latitudes : (Double, Double)
}

///|
pub fn Renderer::draw_fill(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> Unit {
  gl_draw_fill(self.gl, mesh, at.matrix.m, at.clip, r, g, b, a)
}

///|
/// Draws a line layer `width` device pixels wide, plus a pixel of antialiasing.
pub fn Renderer::draw_line(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
  width : Double,
) -> Unit {
  gl_draw_line(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    at.units_per_pixel,
    at.center_depth,
    r,
    g,
    b,
    a,
    width / 2.0 + 0.5,
  )
}

///|
/// Draws circles with `radius` and `stroke_width` in device pixels at the
/// center's depth; `color` and `stroke` are straight RGBA.
pub fn Renderer::draw_circle(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  color : FixedArray[Double],
  stroke : FixedArray[Double],
  radius : Double,
  stroke_width : Double,
) -> Unit {
  gl_draw_circle(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    at.center_depth,
    color,
    stroke,
    radius,
    stroke_width,
  )
}

///|
/// Uploads a `raster-dem` tile's slopes (`@raster.hillshade_slopes`, two bytes
/// per pixel of a `size` x `size` tile) as a texture.
pub fn Renderer::upload_slopes(
  self : Renderer,
  slopes : JsBuffer,
  size : Int32,
) -> Mesh {
  gl_upload_slopes(self.gl, slopes, size)
}

///|
/// Replaces one side's row or column of a slopes texture (0 top, 1 bottom,
/// 2 left, 3 right) with `slopes`, two bytes per pixel along it.
pub fn Renderer::update_slopes(
  self : Renderer,
  mesh : Mesh,
  side : Int32,
  slopes : Bytes,
) -> Unit {
  gl_slopes_side(self.gl, mesh, side, slopes)
}

///|
/// Draws a tile's hillshade (MapLibre's `standard` method): light from
/// `azimuth` radians clockwise from north, colors straight RGBA.
pub fn Renderer::draw_hillshade(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  azimuth : Double,
  exaggeration : Double,
  shadow : FixedArray[Double],
  highlight : FixedArray[Double],
  accent : FixedArray[Double],
) -> Unit {
  gl_draw_hillshade(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    [at.latitudes.0, at.latitudes.1, azimuth, exaggeration],
    shadow,
    highlight,
    accent,
  )
}

///|
/// Pixels per side of the glyph atlas texture.
pub const ATLAS_SIZE : Int32 = 2048

///|
/// Copies a glyph bitmap (one byte per pixel) into the atlas at (x, y).
pub fn Renderer::upload_glyph(
  self : Renderer,
  data : JsBuffer,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
) -> Unit {
  gl_glyph(self.gl, ATLAS_SIZE, ATLAS_SIZE, data, x, y, width, height)
}

///|
/// Uploads a symbol entry's glyph quads; `rects` holds the atlas rectangle
/// (x, y, width, height) of each of its glyphs. No label shows until `show`.
pub fn Renderer::upload_symbols(
  self : Renderer,
  vertices : JsBuffer,
  indices : JsBuffer,
  index_bytes : Int32,
  rects : FixedArray[Int32],
) -> Mesh {
  gl_upload_symbols(self.gl, vertices, indices, index_bytes, rects)
}

///|
/// Shows the labels of a symbol mesh whose flag is set: label `i` owns the
/// indices from `labels[i * stride + stride - 2]`, as many as the float after it.
pub fn Renderer::show(
  self : Renderer,
  mesh : Mesh,
  labels : JsBuffer,
  stride : Int32,
  shown : FixedArray[Bool],
) -> Unit {
  gl_show(self.gl, mesh, labels, stride, shown)
}

///|
/// Draws a symbol mesh's shown labels: the halo first, then the text.
pub fn Renderer::draw_symbols(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  dpr : Double,
  color : FixedArray[Double],
  halo : FixedArray[Double],
  halo_width : Double,
) -> Unit {
  gl_draw_symbols(self.gl, mesh, at.matrix.m, dpr, color, halo, halo_width)
}

///|
/// Gives a `raster-dem` tile's mesh its elevations (`size` x `size` f32s) for
/// terrain.
pub fn Renderer::add_elevations(
  self : Renderer,
  mesh : Mesh,
  elevations : JsBuffer,
  size : Int32,
) -> Unit {
  gl_add_elevations(self.gl, mesh, elevations, size)
}

///|
/// A new offscreen target of `size` x `size` pixels.
pub fn Renderer::target(self : Renderer, size : Int32) -> Target {
  gl_target_new(self.gl, size)
}

///|
pub fn Renderer::release_target(self : Renderer, target : Target) -> Unit {
  gl_target_release(self.gl, target)
}

///|
/// Draws into `target`, cleared to an opaque color, until `end_target`.
pub fn Renderer::begin_target(
  self : Renderer,
  target : Target,
  r : Double,
  g : Double,
  b : Double,
) -> Unit {
  gl_target_begin(self.gl, target, r, g, b)
}

///|
/// Draws into the canvas again.
pub fn Renderer::end_target(self : Renderer) -> Unit {
  gl_target_end(self.gl)
}

///|
/// Clears the canvas's depth, before drawing terrain.
pub fn Renderer::clear_depth(self : Renderer) -> Unit {
  gl_clear_depth(self.gl)
}

///|
/// Draws a terrain tile: `mesh`'s elevations (the part at `dem`: offset x, y and
/// scale in the DEM tile) lift the tile's grid by `scale` world pixels per
/// meter, skirts hang `skirt` world pixels below its edges, and `target` holds
/// what is drawn on it.
pub fn Renderer::draw_terrain(
  self : Renderer,
  mesh : Mesh,
  target : Target,
  at : Placement,
  scale : Double,
  skirt : Double,
  dem : FixedArray[Double],
) -> Unit {
  gl_draw_terrain(self.gl, mesh, target, at.matrix.m, scale, skirt, dem)
}
