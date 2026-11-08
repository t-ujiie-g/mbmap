///|
/// Draws terrain into the depth target until `end_depth`; symbols drawn after
/// that fade where it hides them, until `reset_depth`.
pub fn Renderer::begin_depth(self : Renderer) -> Unit {
  gl_depth_begin(self.gl)
}

///|
pub fn Renderer::end_depth(self : Renderer) -> Unit {
  gl_depth_end(self.gl)
}

///|
/// Symbols are no longer hidden by terrain depth (a frame without terrain).
pub fn Renderer::reset_depth(self : Renderer) -> Unit {
  gl_depth_reset(self.gl)
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
/// Draws a terrain tile: `mesh`'s elevations (`dem`: offset x, y and scale in the DEM tile) lift its
/// grid by `scale` world pixels per meter (meters on the globe, by `per_meter`), with skirts `skirt`
/// deep, `target` on it and `fog` in the distance.
pub fn Renderer::draw_terrain(
  self : Renderer,
  mesh : Mesh,
  target : Target,
  at : Placement,
  scale : Double,
  skirt : Double,
  per_meter : Double,
  dem : FixedArray[Double],
  fog : Fog,
) -> Unit {
  self.use_globe(at.globe)
  gl_draw_terrain(
    self.gl,
    mesh,
    target,
    at.matrix.m,
    scale,
    skirt,
    per_meter,
    dem,
    [fog.near, fog.far, fog.ground_blend, fog.opacity, fog.horizon_blend],
    fog.color,
    fog.horizon,
  )
}

///|
/// MapLibre's terrain fog (premultiplied colors): past `ground_blend` of the depth
/// from `near` to `far` (`@core.Transform::fog_range`), terrain blends into
/// `color`, turning to `horizon` past `horizon_blend`, at most `opacity`.
pub(all) struct Fog {
  near : Double
  far : Double
  ground_blend : Double
  opacity : Double
  horizon_blend : Double
  color : FixedArray[Double]
  horizon : FixedArray[Double]
}

///|
/// Draws the sky above the horizon line `horizon_y` (device pixels from the
/// bottom): `sky` blending into `horizon` over the `blend` pixels above the
/// line. Colors are premultiplied RGBA.
pub fn Renderer::draw_sky(
  self : Renderer,
  horizon_y : Double,
  blend : Double,
  sky : FixedArray[Double],
  horizon : FixedArray[Double],
) -> Unit {
  gl_draw_sky(self.gl, horizon_y, blend, sky, horizon)
}

///|
/// Uploads a fill-extrusion entry; its ground is 0 m until `set_ground`.
pub fn Renderer::upload_extrusion(
  self : Renderer,
  vertices : JsBuffer,
  indices : JsBuffer,
  count : Int32,
  index_bytes : Int32,
) -> Mesh {
  gl_upload_extrusion(self.gl, vertices, indices, count, index_bytes)
}

///|
/// The features of an extrusion entry's `vertices`: for each run of vertices
/// sharing a centroid, its first vertex and the centroid's x and y (tile units).
pub fn extrusion_runs(vertices : JsBuffer) -> FixedArray[Int32] {
  extrusion_runs_of(vertices)
}

///|
/// Sets the ground in meters under each run of `runs` (`extrusion_runs`).
pub fn Renderer::set_ground(
  self : Renderer,
  mesh : Mesh,
  runs : FixedArray[Int32],
  heights : FixedArray[Double],
) -> Unit {
  gl_set_ground(self.gl, mesh, runs, heights)
}

///|
/// How extrusions are lit: `direction` toward the light (x, y, z, in tile
/// axes), `intensity`, `color` (straight RGB) and, on the globe, the direction
/// in its axes (`globe_direction`).
pub(all) struct ExtrusionLight {
  direction : (Double, Double, Double)
  intensity : Double
  color : (Double, Double, Double)
  globe_direction : (Double, Double, Double)
}

///|
/// Draws an extrusion mesh, `color` (or `pattern`) lit by `light`; `t` mixes its
/// heights from the tile's zoom to one deeper, `scale` is world px per meter,
/// `ground` the terrain exaggeration; `pass` 0 at once, else depth (1) then color (2).
pub fn Renderer::draw_extrusion(
  self : Renderer,
  mesh : Mesh,
  at : Placement,
  color : (Double, Double, Double),
  opacity : Double,
  light : ExtrusionLight,
  gradient : Bool,
  t : Double,
  scale : Double,
  ground : Double,
  pattern~ : PatternPosition? = None,
  pass~ : Int32 = 0,
) -> Unit {
  self.use_globe(at.globe)
  let (lx, ly, lz) = light.direction
  let (lr, lg, lb) = light.color
  let program = match pattern {
    Some(pos) => {
      self.use_pattern("extrusionPattern", pos, at.pattern)
      "extrusionPattern"
    }
    None => "extrusion"
  }
  gl_draw_extrusion(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    [color.0, color.1, color.2],
    opacity,
    [
      lx,
      ly,
      lz,
      light.intensity,
      lr,
      lg,
      lb,
      light.globe_direction.0,
      light.globe_direction.1,
      light.globe_direction.2,
    ],
    gradient,
    [t, scale, ground, at.pattern.height_factor],
    program,
    pass,
  )
}

///|
/// Starts the color pass of a translucent extrusion layer: every pixel is then
/// colored once, by its nearest surface.
pub fn Renderer::begin_extrusion_color(self : Renderer) -> Unit {
  gl_clear_stencil(self.gl)
}
