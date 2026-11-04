///|
/// Draws a line layer with `slots`' color, opacity, width, gap width and offset
/// (CSS pixels, times `dpr`), edges faded over `blur` (CSS pixels) and a pixel.
pub fn Renderer::draw_line(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
  dpr : Double,
  blur~ : Double = 0.0,
) -> Unit {
  self.bind("line", mesh, slots, 6)
  gl_draw_line(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    at.units_per_pixel,
    at.center_depth,
    dpr,
    blur * dpr,
  )
}

///|
/// Adds a dashed line mesh's distances along its lines (docs/FORMATS.md,
/// "Packed tile").
pub fn Renderer::upload_distances(
  self : Renderer,
  mesh : Mesh,
  distances : JsBuffer,
) -> Unit {
  gl_upload_distances(self.gl, mesh, distances)
}

///|
/// Adds an offset line mesh's offset normals (docs/FORMATS.md, "Packed tile").
pub fn Renderer::upload_offsets(
  self : Renderer,
  mesh : Mesh,
  offsets : JsBuffer,
) -> Unit {
  gl_upload_offsets(self.gl, mesh, offsets)
}

///|
/// Adds a gradient line mesh's progress (docs/FORMATS.md, "Packed tile").
pub fn Renderer::upload_progress(
  self : Renderer,
  mesh : Mesh,
  progress : JsBuffer,
) -> Unit {
  gl_upload_progress(self.gl, mesh, progress)
}

///|
/// Uploads a line gradient's color ramp (`color_ramp`): `width` pixels per row
/// and a row per line; `nearest` for a step.
pub fn Renderer::upload_gradient(
  self : Renderer,
  pixels : FixedArray[Byte],
  width : Int32,
  height : Int32,
  nearest~ : Bool,
) -> Gradient {
  gl_upload_gradient(self.gl, pixels, width, height, nearest)
}

///|
pub fn Renderer::release_gradient(self : Renderer, g : Gradient) -> Unit {
  gl_release_gradient(self.gl, g)
}

///|
/// Draws a line as `draw_line`, its color from gradient `g` (MapLibre's
/// line_gradient) times `slots`' opacity.
pub fn Renderer::draw_line_gradient(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
  dpr : Double,
  blur~ : Double = 0.0,
  g : Gradient,
) -> Unit {
  self.bind("lineGradient", mesh, slots, 6)
  gl_draw_line_gradient(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    at.units_per_pixel,
    at.center_depth,
    dpr,
    blur * dpr,
    g,
  )
}

///|
/// Where the dash pattern `dasharray` (in line widths; round ends when `round`)
/// lies in the dash atlas; None once it is full.
pub fn Renderer::dash(
  self : Renderer,
  dasharray : Array[Double],
  round : Bool,
) -> DashEntry? {
  self.atlas.dash(dasharray, round)
}

///|
/// Adds a line mesh's dash patterns by feature (docs/FORMATS.md, "Packed tile"):
/// `patterns` as the atlas places them (None where it cannot), `marks` per vertex.
pub fn Renderer::upload_feature_dashes(
  self : Renderer,
  mesh : Mesh,
  patterns : Array[DashEntry?],
  marks : JsBuffer,
) -> Unit {
  let entries = FixedArray::make(patterns.length() * 2, -1.0)
  for k, p in patterns {
    if p is Some(e) {
      entries[k * 2] = (e.y * 64 + e.height).to_double()
      entries[k * 2 + 1] = e.width
    }
  }
  gl_upload_feature_dashes(self.gl, mesh, marks, entries)
}

///|
/// `draw_line_dash` with each feature's patterns (`upload_feature_dashes`),
/// their edges smoothed as zooming in (`zoom_in`: over the shorter of the pattern
/// and the one a zoom out) or out.
pub fn Renderer::draw_line_dash_by_feature(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
  dpr : Double,
  blur~ : Double = 0.0,
  zoom_in~ : Bool,
  px_per_unit~ : Double,
  floor_width~ : Double,
  floor_t~ : Double,
) -> Unit {
  if self.atlas.take_dirty() {
    gl_dash_atlas(self.gl, self.atlas.data, LINE_ATLAS_WIDTH, LINE_ATLAS_HEIGHT)
  }
  self.bind("lineDashFeature", mesh, slots, 6)
  gl_draw_line_dash_feature(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    at.units_per_pixel,
    at.center_depth,
    dpr,
    blur * dpr,
    [
      px_per_unit,
      1.0 / LINE_ATLAS_HEIGHT.to_double(),
      1.0 / dpr,
      if zoom_in {
        1.0
      } else {
        0.0
      },
    ],
    [floor_width, floor_t],
  )
}

///|
/// `draw_line` with dash pattern `entry` (MapLibre's line_sdf; `px_per_unit`: CSS
/// px per tile unit at the integer zoom, `floor_width` the width there, or the
/// width slot mixed `floor_t` when negative; edges smoothed over `gamma_width`).
pub fn Renderer::draw_line_dash(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  slots : PaintSlots,
  dpr : Double,
  blur~ : Double = 0.0,
  entry : DashEntry,
  gamma_width~ : Double,
  px_per_unit~ : Double,
  floor_width~ : Double,
  floor_t~ : Double,
) -> Unit {
  if entry.width <= 0.0 || gamma_width <= 0.0 {
    return
  }
  if self.atlas.take_dirty() {
    gl_dash_atlas(self.gl, self.atlas.data, LINE_ATLAS_WIDTH, LINE_ATLAS_HEIGHT)
  }
  self.bind("lineDash", mesh, slots, 6)
  let h = LINE_ATLAS_HEIGHT.to_double()
  gl_draw_line_dash(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    at.units_per_pixel,
    at.center_depth,
    dpr,
    blur * dpr,
    [
      px_per_unit / entry.width,
      (entry.y.to_double() + 0.5) / h,
      -entry.height.to_double() / 2.0 / h,
      1.0 / dpr / gamma_width,
    ],
    [floor_width, floor_t],
  )
}
