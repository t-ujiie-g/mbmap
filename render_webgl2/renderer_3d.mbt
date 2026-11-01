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
/// Draws a terrain tile: `mesh`'s elevations (the part at `dem`: offset x, y and
/// scale in the DEM tile) lift the tile's grid by `scale` world pixels per
/// meter, skirts hang `skirt` world pixels below its edges, `target` holds
/// what is drawn on it, and `fog` fades it out in the distance.
pub fn Renderer::draw_terrain(
  self : Renderer,
  mesh : Mesh,
  target : Target,
  at : Placement,
  scale : Double,
  skirt : Double,
  dem : FixedArray[Double],
  fog : Fog,
) -> Unit {
  gl_draw_terrain(
    self.gl,
    mesh,
    target,
    at.matrix.m,
    scale,
    skirt,
    dem,
    [fog.near, fog.far, fog.ground_blend, fog.opacity, fog.horizon_blend],
    fog.color,
    fog.horizon,
  )
}

///|
/// Terrain fog as MapLibre draws it: fragments past `ground_blend` of the way
/// from depth `near` to `far` (`@core.Transform::fog_range`, in the depth
/// buffer's nonlinear scale) blend into `color`, which turns towards
/// `horizon` past `horizon_blend`, at most `opacity` of the way. Colors are
/// premultiplied RGBA.
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
/// axes), `intensity`, and `color` (straight RGB).
pub(all) struct ExtrusionLight {
  direction : (Double, Double, Double)
  intensity : Double
  color : (Double, Double, Double)
}

///|
/// Draws an extrusion mesh, `color` (straight RGB) lit by `light` at `opacity`;
/// `t` mixes its heights from the tile's zoom (0) to one deeper (1), `scale`
/// is world pixels per meter and `ground` the terrain exaggeration (0 without
/// terrain).
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
) -> Unit {
  let (lx, ly, lz) = light.direction
  let (lr, lg, lb) = light.color
  gl_draw_extrusion(
    self.gl,
    mesh,
    at.matrix.m,
    at.clip,
    [color.0, color.1, color.2],
    opacity,
    [lx, ly, lz, light.intensity, lr, lg, lb],
    gradient,
    [t, scale, ground],
  )
}
