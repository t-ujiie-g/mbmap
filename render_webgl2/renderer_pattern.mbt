///|
/// Where a tile's patterns start: its top-left corner in CSS pixels of the
/// world at the integer zoom (`x`, `y`), CSS pixels per tile unit there, and
/// tile units per meter up a wall (MapLibre's `u_height_factor`, negative).
pub(all) struct PatternTile {
  x : Double
  y : Double
  units : Double
  height_factor : Double
}

///|
/// Pattern `name`'s place in the atlas, if added.
pub fn Renderer::pattern(self : Renderer, name : String) -> PatternPosition? {
  self.patterns.get(name)
}

///|
/// Adds `image` to the pattern atlas as `name`; None if it does not fit.
pub fn Renderer::add_pattern(
  self : Renderer,
  name : String,
  image : StyleImage,
) -> PatternPosition? {
  self.patterns.add(name, image)
}

///|
/// Empties the pattern atlas, when images change.
pub fn Renderer::clear_patterns(self : Renderer) -> Unit {
  self.patterns.clear()
}

///|
/// Uploads the atlas if it changed and sets program `name`'s pattern uniforms
/// (MapLibre's `patternUniformValues`, the tile's pixel position split in 16-bit
/// halves as there).
fn Renderer::use_pattern(
  self : Renderer,
  name : String,
  pos : PatternPosition,
  tile : PatternTile,
) -> Unit {
  self.upload_patterns()
  let (w, h) = pos.display_size()
  let upper = (v : Double) => (v / 65536.0).floor()
  gl_set_pattern(self.gl, name, [
    w,
    h,
    upper(tile.x),
    upper(tile.y),
    tile.x - upper(tile.x) * 65536.0,
    tile.y - upper(tile.y) * 65536.0,
    tile.units,
    pos.tl.0.to_double(),
    pos.tl.1.to_double(),
    pos.br.0.to_double(),
    pos.br.1.to_double(),
    if pos.sdf {
      1.0
    } else {
      0.0
    },
  ])
}

///|
/// Draws a fill with pattern `pos` (MapLibre's fill_pattern) and `slots`'
/// opacity (and color, for an SDF pattern).
pub fn Renderer::draw_fill_pattern(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
  pos : PatternPosition,
  tile : PatternTile,
) -> Unit {
  self.use_globe(at.globe)
  self.bind("fillPattern", mesh, slots, 2)
  self.use_pattern("fillPattern", pos, tile)
  gl_draw_fill(self.gl, "fillPattern", mesh, at.matrix.m, at.clip)
}

///|
/// Draws a fill's outline in its pattern (MapLibre's fill_outline_pattern).
pub fn Renderer::draw_fill_outline_pattern(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
  pos : PatternPosition,
  tile : PatternTile,
) -> Unit {
  self.use_globe(at.globe)
  self.bind("fillOutlinePattern", mesh, slots, 2)
  self.use_pattern("fillOutlinePattern", pos, tile)
  gl_draw_outline(self.gl, "fillOutlinePattern", mesh, at.matrix.m, at.clip)
}

///|
/// Draws one tile of a background pattern (MapLibre's background_pattern) with
/// `opacity`, and `color` (straight RGBA) for an SDF pattern.
pub fn Renderer::draw_background_pattern(
  self : Renderer,
  matrix : @core.Mat4,
  globe? : GlobeTile,
  pos : PatternPosition,
  tile : PatternTile,
  opacity : Double,
  color : FixedArray[Double],
) -> Unit {
  self.use_pattern("backgroundPattern", pos, tile)
  self.use_globe(globe)
  let a = color[3] * opacity
  gl_draw_background_pattern(self.gl, matrix.m, opacity, [
    color[0] * a,
    color[1] * a,
    color[2] * a,
    a,
  ])
}

///|
/// Uploads the pattern atlas if it changed.
fn Renderer::upload_patterns(self : Renderer) -> Unit {
  if self.patterns.take_dirty() {
    gl_pattern_atlas(
      self.gl,
      "patterns",
      self.patterns.data,
      PATTERN_ATLAS_WIDTH,
      self.patterns.height,
    )
  }
}

///|
/// Draws a line with pattern `pos` (MapLibre's line_pattern), the image as tall
/// as the line's floor width (`floor_width`, or the width slot mixed `floor_t`
/// when negative), times `slots`' opacity.
pub fn Renderer::draw_line_pattern(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
  dpr : Double,
  blur~ : Double = 0.0,
  pos : PatternPosition,
  floor_width~ : Double,
  floor_t~ : Double,
) -> Unit {
  self.use_globe(at.globe)
  self.upload_patterns()
  self.bind("linePattern", mesh, slots, 6)
  let (w, h) = pos.display_size()
  gl_draw_line_pattern(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    at.units_per_pixel,
    at.center_depth,
    dpr,
    blur * dpr,
    [
      pos.tl.0.to_double(),
      pos.tl.1.to_double(),
      pos.br.0.to_double(),
      pos.br.1.to_double(),
      w,
      h,
      at.pattern.units,
      floor_width,
      floor_t,
    ],
  )
}
