///|
/// Draws packed tile layers with WebGL2. Colors are straight RGBA in [0, 1];
/// sizes are in device pixels unless noted.
pub struct Renderer {
  priv gl : Gl
  priv atlas : LineAtlas
  priv patterns : PatternAtlas
  priv icons : PatternAtlas
}

///|
/// None if the canvas cannot provide a WebGL2 context.
pub fn Renderer::new(canvas : Canvas) -> Renderer? {
  let gl = create_gl(canvas)
  if is_null(gl) {
    None
  } else {
    Some({
      gl,
      atlas: LineAtlas::new(),
      patterns: PatternAtlas::new(),
      icons: PatternAtlas::new(wrap=false),
    })
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
  pattern : PatternTile
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
/// Binds `mesh` and the first `count` paint slots to `program` (`@style.SLOT_*`:
/// 2 color and opacity, 3 also size, 4 also stroke color, 6 all).
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
  gl_draw_fill(self.gl, "fill", mesh, at.matrix.m, at.clip)
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
  gl_draw_outline(self.gl, "fillOutline", mesh, at.matrix.m, at.clip)
}

///|
/// Draws circles with `slots`' paint, sizes in CSS pixels times `dpr`: facing the
/// viewer or lying on the map (`pitch_with_map`), grown with the map or kept on
/// screen (not `scale_with_map`), edges faded over `blur` (a share of the size).
pub fn Renderer::draw_circle(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
  dpr : Double,
  scale_with_map~ : Bool = true,
  pitch_with_map~ : Bool = false,
  blur~ : Double = 0.0,
) -> Unit {
  self.bind("circle", mesh, slots, 6)
  let flag = (b : Bool) => if b { 1.0 } else { 0.0 }
  gl_draw_circle(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    at.center_depth,
    dpr,
    at.units_per_pixel,
    [flag(scale_with_map), flag(pitch_with_map), blur],
  )
}

///|
/// Uploads a `raster-dem` tile's slopes (`@raster.hillshade_slopes`, two bytes
/// per pixel of a `size` x `size` tile and its border) as a texture.
pub fn Renderer::upload_slopes(
  self : Renderer,
  slopes : JsBuffer,
  size : Int32,
) -> Mesh {
  gl_upload_slopes(self.gl, slopes, size)
}

///|
/// Replaces one side's row or column of a slopes texture (0 top, 1 bottom,
/// 2 left, 3 right), or of its `border`, with `slopes`, two bytes per pixel.
pub fn Renderer::update_slopes(
  self : Renderer,
  mesh : Mesh,
  side : Int32,
  slopes : Bytes,
  border~ : Bool = false,
) -> Unit {
  gl_slopes_side(self.gl, mesh, side, slopes, border)
}

///|
/// Draws a tile's hillshade by `shading` (MapLibre's `u_method`). Per light,
/// `angles` holds its azimuth (clockwise from north) and altitude in radians,
/// `colors` its shadow and highlight color (straight RGBA).
pub fn Renderer::draw_hillshade(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  shading~ : Int32,
  exaggeration~ : Double,
  angles~ : FixedArray[Double],
  colors~ : FixedArray[Double],
  accent~ : FixedArray[Double],
  nearest~ : Bool,
) -> Unit {
  gl_draw_hillshade(
    self.gl,
    mesh,
    at.raster_matrix.m,
    at.clip,
    [
      at.latitudes.0,
      at.latitudes.1,
      exaggeration,
      shading.to_double(),
      (angles.length() / 2).to_double(),
      if nearest {
        1.0
      } else {
        0.0
      },
    ],
    angles,
    colors,
    accent,
  )
}

///|
/// Gives a DEM tile's mesh its `heights` (a Float32Array of `size` x `size`)
/// for color relief layers, packed into RGB by `unpack` (red, green and blue
/// factors and base shift, as MapLibre's `getUnpackVector`).
pub fn Renderer::relief_heights(
  self : Renderer,
  mesh : Mesh,
  heights : JsBuffer,
  size : Int32,
  unpack : FixedArray[Double],
) -> Unit {
  gl_relief_heights(self.gl, mesh, heights, size, unpack)
}

///|
/// Whether `relief_heights` gave the mesh its heights.
pub fn Renderer::has_relief(_ : Renderer, mesh : Mesh) -> Bool {
  gl_has_relief(mesh)
}

///|
/// Fills the border of a mesh's `relief_heights` from the `heights` of the
/// same-size tile (`dx`, `dy`) beside it.
pub fn Renderer::relief_border(
  self : Renderer,
  mesh : Mesh,
  heights : JsBuffer,
  size : Int32,
  unpack : FixedArray[Double],
  dx~ : Int32,
  dy~ : Int32,
) -> Unit {
  gl_relief_border(self.gl, mesh, heights, size, unpack, dx, dy)
}

///|
/// A color relief's ramp: straight RGBA `colors` (bytes) at elevation `stops`,
/// which `unpack` packs as `relief_heights` does. Freed by `release_gradient`.
pub fn Renderer::relief_ramp(
  self : Renderer,
  stops : FixedArray[Double],
  colors : FixedArray[Byte],
  unpack : FixedArray[Double],
) -> Gradient {
  let g = gl_upload_gradient(self.gl, colors, stops.length(), 1, false)
  gl_relief_ramp(self.gl, g, stops, unpack)
  g
}

///|
/// Draws a tile's color relief (MapLibre's color_relief) from the heights given
/// by `relief_heights` with `ramp`.
pub fn Renderer::draw_relief(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  ramp : Gradient,
  unpack : FixedArray[Double],
  opacity~ : Double,
  nearest~ : Bool,
) -> Unit {
  gl_draw_relief(self.gl, mesh, at.raster_matrix.m, at.clip, ramp, unpack, [
    opacity,
    if nearest {
      1.0
    } else {
      0.0
    },
  ])
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
  colors~ : JsBuffer = undefined_buffer(),
) -> Mesh {
  gl_upload_symbols(self.gl, vertices, indices, index_bytes, rects, colors)
}

///|
/// No buffer (JS undefined).
extern "js" fn undefined_buffer() -> JsBuffer =
  #|() => undefined

///|
/// Shows the labels of a symbol mesh whose flag is set, each in its layout
/// `variant`: label `i` owns as many layouts as `labels[i * stride + col]`, each
/// of the index count two floats after, from the index between.
pub fn Renderer::show(
  self : Renderer,
  mesh : Mesh,
  labels : JsBuffer,
  stride : Int32,
  shown : FixedArray[Bool],
  variant : FixedArray[Int32],
  col~ : Int32,
) -> Unit {
  gl_show(self.gl, mesh, labels, stride, col, shown, variant)
}

///|
/// Moves each label of a symbol mesh by its shift (`shifts`: x and y in CSS px
/// per label, laid out as for `show`), smaller in the distance like the text.
pub fn Renderer::set_shifts(
  self : Renderer,
  mesh : Mesh,
  labels : JsBuffer,
  stride : Int32,
  shifts : FixedArray[Double],
  col~ : Int32,
) -> Unit {
  gl_set_shifts(self.gl, mesh, labels, stride, col, shifts)
}

///|
/// Draws a symbol mesh's shown labels with MapLibre's symbol_sdf (colors straight RGBA with `opacity`
/// in, which `format` sections' colors also take; the halo in a pass first if `two_pass`), raised by
/// `set_heights` times `height_scale` and faded behind terrain drawn by `begin_depth`.
pub fn Renderer::draw_symbols(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  dpr : Double,
  color : FixedArray[Double],
  halo : FixedArray[Double],
  halo_width : Double,
  halo_blur~ : Double = 0.0,
  two_pass~ : Bool = true,
  opacity~ : Double = 1.0,
  gamma_scale~ : Double = 1.0,
  height_scale~ : Double = 0.0,
) -> Unit {
  gl_draw_symbols(
    self.gl,
    mesh,
    at.matrix.m,
    dpr,
    color,
    halo,
    [
      halo_width,
      halo_blur,
      if two_pass {
        1.0
      } else {
        0.0
      },
      opacity,
      gamma_scale,
    ],
    at.center_depth,
    height_scale,
    at.units_per_pixel * dpr,
  )
}

///|
/// Places the glyphs of a mesh of labels along lines (`glyphs`: x, y in tile
/// units and angle in radians per glyph quad, x below -1e8 hiding it), which
/// `draw_symbols` then lays on the map.
pub fn Renderer::set_glyphs(
  self : Renderer,
  mesh : Mesh,
  glyphs : FixedArray[Double],
) -> Unit {
  gl_set_glyphs(self.gl, mesh, glyphs)
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
  col~ : Int32,
) -> Unit {
  gl_set_heights(self.gl, mesh, labels, stride, col, heights)
}

///|
extern "js" fn gl_set_range(
  mesh : Mesh,
  first : Int32,
  count : Int32,
  outline : Bool,
) -> Unit =
  #|(m, first, count, outline) => {
  #|  const [o, n] = outline ? ["outlineOffset", "outlineRange"] : ["rangeOffset", "rangeCount"];
  #|  if (count < 0) { delete m[o]; delete m[n]; return; }
  #|  m[o] = first * (m.type === 0x1405 ? 4 : 2);
  #|  m[n] = count;
  #|}

///|
/// Makes fill, line, circle and extrusion draws of `mesh` (its fill outline's,
/// when `outline`) take only indices `first..<first + count` (feature by
/// feature drawing), until `whole_mesh`.
pub fn Renderer::set_range(
  _self : Renderer,
  mesh : Mesh,
  first : Int32,
  count : Int32,
  outline~ : Bool = false,
) -> Unit {
  gl_set_range(mesh, first, count, outline)
}

///|
/// Draws all of `mesh` again after `set_range`.
pub fn Renderer::whole_mesh(_self : Renderer, mesh : Mesh) -> Unit {
  gl_set_range(mesh, 0, -1, false)
  gl_set_range(mesh, 0, -1, true)
}

///|
extern "js" fn gl_index_count(mesh : Mesh, outline : Bool) -> Int32 =
  #|(m, outline) => outline ? (m.outlineCount ?? 0) : m.count

///|
/// How many indices `mesh` holds (those of its fill outline when `outline`).
pub fn Renderer::index_count(
  _self : Renderer,
  mesh : Mesh,
  outline~ : Bool = false,
) -> Int32 {
  gl_index_count(mesh, outline)
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

///|
/// The map's WebGL2RenderingContext, for custom layers.
#external
pub type Context

///|
extern "js" fn gl_context(gl : Gl) -> Context = "(c) => c.gl"

///|
pub fn Renderer::context(self : Renderer) -> Context {
  gl_context(self.gl)
}

///|
/// An image, video or canvas element, or an ImageBitmap (a WebGL
/// `TexImageSource`), drawn by an image, video or canvas source.
#external
pub type Picture

///|
extern "js" fn null_mesh() -> Mesh = "() => null"

///|
extern "js" fn mesh_is_null(m : Mesh) -> Bool = "(m) => m == null"

///|
/// Uploads `picture` into `old`'s texture, or a new mesh's; `old` unchanged
/// while a video has no frame yet or a canvas no pixels.
pub fn Renderer::upload_picture(
  self : Renderer,
  picture : Picture,
  old : Mesh?,
) -> Mesh? {
  let m = gl_upload_picture(self.gl, picture, old.unwrap_or(null_mesh()))
  if mesh_is_null(m) {
    None
  } else {
    Some(m)
  }
}

///|
/// Places a picture's mesh by `quad` (as `@map.Map::set_media_quad` takes it):
/// `draw_raster` then draws it with its corners and warp.
pub fn Renderer::set_quad(
  _self : Renderer,
  mesh : Mesh,
  quad : FixedArray[Double],
) -> Unit {
  gl_set_quad(mesh, quad)
}
