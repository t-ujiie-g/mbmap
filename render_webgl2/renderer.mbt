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
/// Where a mesh is drawn: `matrix` (and `raster_matrix`, on the pixel grid at
/// rest) maps tile units to clip space; `units_per_pixel` at `center_depth`; only
/// `clip` (tile units) shows; `latitudes` are the tile's north and south edges.
pub(all) struct Placement {
  matrix : @core.Mat4
  raster_matrix : @core.Mat4
  units_per_pixel : Double
  center_depth : Double
  clip : FixedArray[Double]
  latitudes : (Double, Double)
}

///|
/// An empty set of paint slots for one draw.
pub fn PaintSlots::new() -> PaintSlots {
  paint_slots_new()
}

///|
/// Slot `slot` holds a constant: a straight RGBA color, or a number in `a`.
pub fn PaintSlots::constant(
  self : PaintSlots,
  slot : Int32,
  a : Double,
  b~ : Double = 0.0,
  c~ : Double = 0.0,
  d~ : Double = 0.0,
) -> Unit {
  paint_slots_constant(self, slot, a, b, c, d)
}

///|
/// Slot `slot` reads `buffer`'s values `offset` bytes into each vertex of
/// `stride` bytes (the value the zoom position starts from), mixed `t` of the
/// way to the next; `single` when it stores one value.
pub fn PaintSlots::per_vertex(
  self : PaintSlots,
  slot : Int32,
  buffer : PaintBuffer,
  offset : Int32,
  stride : Int32,
  t : Double,
  single~ : Bool,
) -> Unit {
  paint_slots_buffer(self, slot, buffer, offset, stride, t, single)
}

///|
/// Uploads a layer's per-vertex paint (docs/FORMATS.md, "Vertex paint").
pub fn Renderer::upload_paint(self : Renderer, data : JsBuffer) -> PaintBuffer {
  gl_upload_paint(self.gl, data)
}

///|
pub fn Renderer::release_paint(self : Renderer, buffer : PaintBuffer) -> Unit {
  gl_release_paint(self.gl, buffer)
}

///|
/// Binds `mesh` and the first `count` paint slots to `program`.
fn Renderer::bind(
  self : Renderer,
  program : String,
  mesh : Mesh,
  slots : PaintSlots,
  count : Int32,
) -> Unit {
  gl_use(self.gl, program, mesh)
  gl_bind_paint(self.gl, program, slots, count)
}

///|
/// Draws a fill layer with `slots`' color and opacity.
pub fn Renderer::draw_fill(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
) -> Unit {
  self.bind("fill", mesh, slots, 2)
  gl_draw_fill(self.gl, mesh, at.matrix.m, at.clip)
}

///|
/// Adds a fill mesh's outline, `count` indices (vertex pairs, one per edge).
pub fn Renderer::upload_outline(
  self : Renderer,
  mesh : Mesh,
  indices : JsBuffer,
  count : Int32,
) -> Unit {
  gl_upload_outline(self.gl, mesh, indices, count)
}

///|
/// Draws a fill mesh's outline (MapLibre's `fill-antialias`) with `slots`'
/// stroke color (the outline color) and opacity.
pub fn Renderer::draw_fill_outline(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
) -> Unit {
  self.bind("fillOutline", mesh, slots, 4)
  gl_draw_outline(self.gl, mesh, at.matrix.m, at.clip)
}

///|
/// Draws a line layer with `slots`' color, opacity and width (CSS pixels,
/// times `dpr`), plus a pixel of antialiasing.
pub fn Renderer::draw_line(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
  dpr : Double,
) -> Unit {
  self.bind("line", mesh, slots, 3)
  gl_draw_line(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    at.units_per_pixel,
    at.center_depth,
    dpr,
  )
}

///|
/// Draws circles with `slots`' paint, sizes in CSS pixels times `dpr` at the
/// center's depth.
pub fn Renderer::draw_circle(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
  dpr : Double,
) -> Unit {
  self.bind("circle", mesh, slots, 6)
  gl_draw_circle(self.gl, mesh, at.matrix.m, at.clip, at.center_depth, dpr)
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
/// Draws a symbol mesh's shown labels: the halo first, then the text, smaller
/// in the distance, raised by their heights (`set_heights`) times
/// `height_scale` and faded out behind terrain drawn by `begin_depth`.
pub fn Renderer::draw_symbols(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  dpr : Double,
  color : FixedArray[Double],
  halo : FixedArray[Double],
  halo_width : Double,
  height_scale~ : Double = 0.0,
) -> Unit {
  gl_draw_symbols(
    self.gl,
    mesh,
    at.matrix.m,
    dpr,
    color,
    halo,
    halo_width,
    at.center_depth,
    height_scale,
  )
}

///|
/// Sets each label's anchor elevation in meters (`heights`, one per label of
/// `labels`, laid out as for `show`), raised by `draw_symbols`' `height_scale`.
pub fn Renderer::set_heights(
  self : Renderer,
  mesh : Mesh,
  labels : JsBuffer,
  stride : Int32,
  heights : FixedArray[Double],
) -> Unit {
  gl_set_heights(self.gl, mesh, labels, stride, heights)
}

///|
extern "js" fn gl_set_range(mesh : Mesh, first : Int32, count : Int32) -> Unit =
  #|(m, first, count) => {
  #|  if (count < 0) { delete m.rangeOffset; delete m.rangeCount; return; }
  #|  m.rangeOffset = first * (m.type === 0x1405 ? 4 : 2);
  #|  m.rangeCount = count;
  #|}

///|
/// Makes fill, line, circle and extrusion draws of `mesh` take only indices
/// `first..<first + count` (feature by feature drawing), until `whole_mesh`.
pub fn Renderer::set_range(
  _self : Renderer,
  mesh : Mesh,
  first : Int32,
  count : Int32,
) -> Unit {
  gl_set_range(mesh, first, count)
}

///|
/// Draws all of `mesh` again after `set_range`.
pub fn Renderer::whole_mesh(_self : Renderer, mesh : Mesh) -> Unit {
  gl_set_range(mesh, 0, -1)
}

///|
extern "js" fn gl_index_count(mesh : Mesh) -> Int32 =
  #|(m) => m.count

///|
/// How many indices `mesh` holds.
pub fn Renderer::index_count(_self : Renderer, mesh : Mesh) -> Int32 {
  gl_index_count(mesh)
}

///|
/// Uploads a raster tile's image (an ImageBitmap, closed after).
pub fn Renderer::upload_raster(self : Renderer, image : JsBuffer) -> Mesh {
  gl_upload_raster(self.gl, image)
}

///|
/// Draws a raster tile with MapLibre's raster paint: `hue_rotate` in degrees,
/// the others as the style gives them (see `@style.RasterPaint`).
pub fn Renderer::draw_raster(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  opacity~ : Double,
  hue_rotate~ : Double,
  brightness_min~ : Double,
  brightness_max~ : Double,
  saturation~ : Double,
  contrast~ : Double,
  nearest~ : Bool,
) -> Unit {
  let angle = hue_rotate * @math.PI / 180.0
  let s = @math.sin(angle)
  let c = @math.cos(angle)
  let root3 = 3.0.sqrt()
  gl_draw_raster(
    self.gl,
    mesh,
    at.raster_matrix.m,
    at.clip,
    [
      opacity,
      brightness_min,
      brightness_max,
      if saturation > 0.0 {
        1.0 - 1.0 / (1.001 - saturation)
      } else {
        -saturation
      },
      if contrast > 0.0 {
        1.0 / (1.0 - contrast)
      } else {
        1.0 + contrast
      },
      (2.0 * c + 1.0) / 3.0,
      (-root3 * s - c + 1.0) / 3.0,
      (root3 * s - c + 1.0) / 3.0,
    ],
    nearest,
  )
}
