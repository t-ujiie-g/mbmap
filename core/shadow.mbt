///|
/// Texels per edge of the shadow map.
pub const SHADOW_MAP_SIZE : Int32 = 2048

///|
/// Heights in meters a shadow map holds casters up to, and receivers up to.
const SHADOW_CASTERS : Double = 1000.0

///|
const SHADOW_RECEIVERS : Double = 500.0

///|
/// MapLibre's globe radius in meters (`GLOBE_RADIUS`).
const GLOBE_RADIUS : Double = 6371008.8

///|
/// A shadow map's view: `matrix` takes points to the light's clip space (an
/// orthographic view along the light, depth growing away from it) and `texel`
/// is the depth (0 to 1) one texel across spans.
pub(all) struct ShadowView {
  matrix : Mat4
  texel : Double
}

///|
fn dot3(a : (Double, Double, Double), b : (Double, Double, Double)) -> Double {
  a.0 * b.0 + a.1 * b.1 + a.2 * b.2
}

///|
fn cross3(
  a : (Double, Double, Double),
  b : (Double, Double, Double),
) -> (Double, Double, Double) {
  (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
}

///|
fn unit3(a : (Double, Double, Double)) -> (Double, Double, Double) {
  let n = dot3(a, a).sqrt()
  (a.0 / n, a.1 / n, a.2 / n)
}

///|
/// The view along `toward` (unit, to the light) holding `corners` (the
/// receivers' box), its depth reaching `reach` farther toward the light for
/// casters; `up` is the local vertical, `east` the axis taken when the light
/// is straight above.
fn light_view(
  toward : (Double, Double, Double),
  up : (Double, Double, Double),
  east : (Double, Double, Double),
  corners : Array[(Double, Double, Double)],
  reach : Double,
) -> ShadowView {
  let across = cross3(up, toward)
  let right = if dot3(across, across) < 1.0e-12 { east } else { unit3(across) }
  let side = cross3(toward, right)
  let inf = @double.infinity
  let mut x0 = inf
  let mut x1 = -inf
  let mut y0 = inf
  let mut y1 = -inf
  let mut z0 = inf
  let mut z1 = -inf
  for c in corners {
    let (x, y, z) = (dot3(c, right), dot3(c, side), dot3(c, toward))
    x0 = @cmp.minimum(x0, x)
    x1 = @cmp.maximum(x1, x)
    y0 = @cmp.minimum(y0, y)
    y1 = @cmp.maximum(y1, y)
    z0 = @cmp.minimum(z0, z)
    z1 = @cmp.maximum(z1, z)
  }
  z1 += reach
  let (sx, sy, sz) = (2.0 / (x1 - x0), 2.0 / (y1 - y0), -2.0 / (z1 - z0))
  let m = FixedArray::make(16, 0.0)
  for c, v in [right, side, toward] {
    let k = [sx, sy, sz][c]
    m[0 * 4 + c] = v.0 * k
    m[1 * 4 + c] = v.1 * k
    m[2 * 4 + c] = v.2 * k
  }
  m[12] = -(x1 + x0) / (x1 - x0)
  m[13] = -(y1 + y0) / (y1 - y0)
  m[14] = (z1 + z0) / (z1 - z0)
  m[15] = 1.0
  let texel = @cmp.maximum(x1 - x0, y1 - y0) / SHADOW_MAP_SIZE.to_double()
  { matrix: { m, }, texel: texel / (z1 - z0), }
}

///|
/// The ground radius a shadow map covers around the center, in world pixels:
/// wider as the camera tilts and sees farther.
fn Transform::shadow_radius(self : Transform) -> Double {
  center_distance(self.height) *
  (0.8 + 2.0 * @math.sin(radians(self.camera.pitch)))
}

///|
/// The shadow map's view for a light toward `sun` (east, north, up) over world
/// pixels relative to the center (x east, y south, z up, as `view` takes them).
pub fn Transform::shadow_view(
  self : Transform,
  sun : (Double, Double, Double),
) -> ShadowView {
  let toward = unit3((sun.0, -sun.1, sun.2))
  let ppm = self.pixels_per_meter()
  let r = self.shadow_radius()
  let ground = self.elevation * ppm
  let top = ground + @cmp.minimum(r, SHADOW_RECEIVERS * ppm)
  let corners = []
  for x in [-r, r] {
    for y in [-r, r] {
      corners.push((x, y, ground))
      corners.push((x, y, top))
    }
  }
  let reach = SHADOW_CASTERS * ppm / @cmp.maximum(toward.2, 0.17)
  light_view(toward, (0.0, 0.0, 1.0), (1.0, 0.0, 0.0), corners, reach)
}

///|
/// The shadow map's view over MapLibre's unit sphere (the globe's points, 1 the
/// globe's radius) around the center, for a light toward `sun` (east, north, up
/// at the center).
pub fn Transform::shadow_sphere_view(
  self : Transform,
  sun : (Double, Double, Double),
) -> ShadowView {
  let (lng, lat) = (
    radians(self.camera.center.lng),
    radians(self.camera.center.lat),
  )
  let (sl, cl, sp, cp) = (
    @math.sin(lng),
    @math.cos(lng),
    @math.sin(lat),
    @math.cos(lat),
  )
  let up = (sl * cp, sp, cl * cp)
  let east = (cl, 0.0, -sl)
  let north = (-sl * sp, cp, -cl * sp)
  let at = (e : Double, n : Double, u : Double) => {
    (
      e * east.0 + n * north.0 + u * up.0,
      e * east.1 + n * north.1 + u * up.1,
      e * east.2 + n * north.2 + u * up.2,
    )
  }
  let toward = unit3(at(sun.0, sun.1, sun.2))
  let r = self.shadow_radius() / self.pixels_per_meter() / GLOBE_RADIUS
  let top = @cmp.minimum(r, SHADOW_RECEIVERS / GLOBE_RADIUS)
  let corners = []
  for x in [-r, r] {
    for y in [-r, r] {
      for z in [0.0, top] {
        // The sphere bends below the box's plane by about r² / 2.
        let (a, b, c) = at(x, y, z - (if z == 0.0 { r * r } else { 0.0 }))
        corners.push((up.0 + a, up.1 + b, up.2 + c))
      }
    }
  }
  let reach = SHADOW_CASTERS /
    GLOBE_RADIUS /
    @cmp.maximum(dot3(toward, up), 0.17)
  light_view(toward, up, east, corners, reach)
}

///|
/// `light` (over world pixels relative to the center, as `shadow_view`'s) for
/// tile units (`extent` per edge) of `tile`, as `tile_matrix` is for the view.
pub fn Transform::tile_light_matrix(
  self : Transform,
  light : Mat4,
  tile : TileId,
  extent : Int32,
) -> Mat4 {
  let ws = self.world_size()
  let tiles = (1 << tile.z).to_double()
  let c = self.camera.center.to_mercator()
  let units = self.tile_scale(tile, extent)
  light
  .translate(
    (tile.x.to_double() / tiles - c.x) * ws,
    (tile.y.to_double() / tiles - c.y) * ws,
    0.0,
  )
  .scale(units, units, 1.0)
}
