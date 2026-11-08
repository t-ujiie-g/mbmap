///|
/// Where icon `name` lies in the icon atlas, adding `image` if it is not there
/// (padded by a transparent pixel, as MapLibre's `ImageAtlas` pads icons).
pub fn Renderer::icon(
  self : Renderer,
  name : String,
  image : StyleImage,
) -> PatternPosition? {
  match self.icons.get(name) {
    Some(p) => Some(p)
    None => self.icons.add(name, image)
  }
}

///|
/// Puts `image` in place of icon `name`'s, if it is in the atlas: over its
/// pixels when it has their size (meshes drawing it stay valid), else apart.
pub fn Renderer::update_icon(
  self : Renderer,
  name : String,
  image : StyleImage,
) -> Unit {
  if self.icons.get(name) is Some(_) {
    self.icons.put(name, image) |> ignore
  }
}

///|
/// Draws a symbol mesh's shown icons (MapLibre's symbol_icon, or symbol_sdf with
/// `color` and `halo`, straight RGBA): `size` negative for each vertex's; icons
/// `pitch` with the map turned by `angle` (radians) and, `along` lines, by `set_glyphs`.
pub fn Renderer::draw_icons(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  dpr : Double,
  size~ : Double,
  perspective~ : Bool,
  pitch~ : Bool,
  rotate~ : Bool,
  angle~ : Double,
  sdf~ : Bool,
  linear~ : Bool,
  opacity~ : Double,
  color~ : FixedArray[Double],
  halo~ : FixedArray[Double],
  halo_width~ : Double,
  halo_blur~ : Double,
  gamma_scale~ : Double,
  height_scale~ : Double = 0.0,
  along~ : Bool = false,
) -> Unit {
  if self.icons.take_dirty() {
    gl_pattern_atlas(
      self.gl,
      "icons",
      self.icons.data,
      PATTERN_ATLAS_WIDTH,
      self.icons.height,
    )
  }
  let b = (v : Bool) => if v { 1.0 } else { 0.0 }
  self.use_globe(at.globe)
  gl_draw_icons(
    self.gl,
    mesh,
    at.matrix.m,
    [
      dpr,
      at.center_depth,
      height_scale,
      size,
      b(perspective),
      b(pitch),
      b(rotate),
      angle,
      at.units_per_pixel * dpr,
      opacity,
      b(sdf),
      halo_width,
      halo_blur,
      gamma_scale,
      b(linear),
      b(along),
    ],
    color,
    halo,
  )
}
