///|
/// CSS pixels per tile edge at integer zooms, as in MapLibre: the world is
/// `TILE_SIZE * 2^zoom` pixels wide.
pub const TILE_SIZE : Double = 512.0

///|
/// Tile units per tile edge in packed tiles, MapLibre's `EXTENT`: workers
/// rescale every layer to it.
pub const TILE_EXTENT : Int32 = 8192

///|
/// Highest pitch in degrees, as in MapLibre. Above about 70° the horizon comes
/// on screen: the ground ends there (`Transform::horizon`) and the sky begins.
pub const MAX_PITCH : Double = 85.0

///|
/// The ground is drawn up to this share of the way to the true horizon, and
/// never past this many degrees from straight down (MapLibre's
/// `getMercatorHorizon`), so the far plane stays finite.
const HORIZON_SHARE : Double = 0.85

///|
const MAX_HORIZON_ANGLE : Double = 89.25

///|
/// Vertical field of view in radians, MapLibre's default (about 36.87°).
pub const FIELD_OF_VIEW : Double = 0.6435011087932844

///|
/// Where the map looks: its center and zoom, `bearing` in degrees clockwise
/// from north (the direction screen-up points to) and `pitch` in degrees from
/// looking straight down.
#derive(Debug, Eq)
pub(all) struct Camera {
  center : LngLat
  zoom : Double
  bearing : Double
  pitch : Double
}

///|
/// What a camera may do: zoom and pitch ranges and, if set, `bounds` the
/// view may not leave (MapLibre's `maxBounds`).
#derive(Debug, Eq)
pub(all) struct Limits {
  min_zoom : Double
  max_zoom : Double
  min_pitch : Double
  max_pitch : Double
  bounds : LngLatBounds?
}

///|
/// Zoom 0 to 22, pitch 0 to `MAX_PITCH`, no bounds.
pub fn Limits::default() -> Limits {
  {
    min_zoom: 0.0,
    max_zoom: 22.0,
    min_pitch: 0.0,
    max_pitch: MAX_PITCH,
    bounds: None,
  }
}

///|
/// A camera on a `width` x `height` CSS-pixel viewport, kept to `limits` and the
/// latitude limits as MapLibre keeps it, in world pixels relative to the center;
/// `elevation` (meters) lifts the center onto terrain.
pub struct Transform {
  camera : Camera
  width : Double
  height : Double
  limits : Limits
  elevation : Double
  priv view : Mat4
  priv inverse : Mat4
}

///|
pub fn Transform::new(
  camera : Camera,
  width : Double,
  height : Double,
  limits~ : Limits = Limits::default(),
) -> Transform {
  let camera = if finite(camera) {
    camera
  } else {
    { center: { lng: 0.0, lat: 0.0, }, zoom: 0.0, bearing: 0.0, pitch: 0.0, }
  }
  make(constrain(camera, limits, width, height), width, height, limits, 0.0)
}

///|
fn make(
  camera : Camera,
  width : Double,
  height : Double,
  limits : Limits,
  elevation : Double,
) -> Transform {
  let lift = elevation * pixels_per_meter(camera.zoom, camera.center.lat)
  let view = view_projection(camera, width, height, lift)
  {
    camera,
    width,
    height,
    limits,
    elevation,
    view,
    inverse: view.invert().unwrap_or(Mat4::identity()),
  }
}

///|
/// `degrees` in radians.
pub fn radians(degrees : Double) -> Double {
  degrees * @math.PI / 180.0
}

///|
/// Distance from the camera to the center, in CSS pixels.
fn center_distance(height : Double) -> Double {
  height / 2.0 / @math.tan(FIELD_OF_VIEW / 2.0)
}

///|
/// World pixels relative to the center (y south, z up) to clip space, as MapLibre
/// builds it; `lift` world pixels lower the world so the center sits on terrain.
fn view_projection(
  camera : Camera,
  width : Double,
  height : Double,
  lift : Double,
) -> Mat4 {
  let d = center_distance(height)
  let far = far_distance(camera.pitch, height, lift)
  Mat4::perspective(FIELD_OF_VIEW, width / height, height / 50.0, far)
  .scale(1.0, -1.0, 1.0)
  .translate(0.0, 0.0, -d)
  .rotate_x(radians(camera.pitch))
  .rotate_z(-radians(camera.bearing))
  .translate(0.0, 0.0, -lift)
}

///|
/// Depth (CSS pixels along the view axis) of the farthest ground drawn, as
/// MapLibre's `_calculateNearFarZ`: the screen's top or the horizon line on the
/// sea-level plane (the center's, when `lift` is below sea level).
fn far_distance(pitch : Double, height : Double, lift : Double) -> Double {
  let d = center_distance(height)
  let limited = radians(@cmp.minimum(pitch, MAX_HORIZON_ANGLE))
  let sea = @cmp.maximum(d / 2.0, d + lift / @math.cos(limited))
  let lowest = if lift < 0.0 { sea - lift / @math.cos(limited) } else { sea }
  let ground = @math.PI / 2.0 + radians(pitch)
  let surface = (angle : Double) => {
    @math.sin(angle) *
    lowest /
    @math.sin(
      @cmp.maximum(
        0.01,
        @cmp.minimum(@math.PI - 0.01, @math.PI - ground - angle),
      ),
    )
  }
  let to_horizon = @cmp.maximum(
    @math.atan(horizon_distance(pitch, height) / d),
    radians(90.0 - MAX_HORIZON_ANGLE),
  )
  let top = @cmp.minimum(surface(FIELD_OF_VIEW / 2.0), surface(to_horizon))
  (@math.sin(limited) * top + lowest) * 1.01
}

///|
/// The depths (CSS pixels along the view axis) over which terrain fog is
/// measured, as in MapLibre's fog matrix: from the camera's distance to sea
/// level to the far plane.
pub fn Transform::fog_range(self : Transform) -> (Double, Double) {
  let d = center_distance(self.height)
  let lift = self.elevation * self.pixels_per_meter()
  let pitch = radians(@cmp.minimum(self.camera.pitch, MAX_HORIZON_ANGLE))
  (
    @cmp.maximum(d / 2.0, d + lift / @math.cos(pitch)),
    far_distance(self.camera.pitch, self.height, lift),
  )
}

///|
/// CSS pixels from the screen center up to the horizon line (MapLibre's
/// `getMercatorHorizon`); beyond the screen's top edge below about 70°.
fn horizon_distance(pitch : Double, height : Double) -> Double {
  center_distance(height) *
  @cmp.minimum(
    @math.tan(radians(90.0 - pitch)) * HORIZON_SHARE,
    @math.tan(radians(MAX_HORIZON_ANGLE - pitch)),
  )
}

///|
/// CSS pixels from the screen center up to the horizon line, above which the
/// sky is drawn and no point maps to the ground.
pub fn Transform::horizon(self : Transform) -> Double {
  horizon_distance(self.camera.pitch, self.height)
}

///|
/// The circumference MapLibre measures heights in: a sphere of the Earth's
/// mean radius, 6371008.8 m (its `earthCircumference`).
const EARTH_CIRCUMFERENCE : Double = 2.0 * @math.PI * 6371008.8

///|
/// World pixels per meter of height at `lat`, zoom `zoom` (MapLibre's
/// mercatorZfromAltitude scaled to the world).
fn pixels_per_meter(zoom : Double, lat : Double) -> Double {
  TILE_SIZE *
  @math.pow(2.0, zoom) /
  (EARTH_CIRCUMFERENCE * @math.cos(radians(lat)))
}

///|
/// World pixels per meter of height at the center, for lifting terrain.
pub fn Transform::pixels_per_meter(self : Transform) -> Double {
  pixels_per_meter(self.camera.zoom, self.camera.center.lat)
}

///|
/// The same view with the center at `elevation` meters (terrain under it).
pub fn Transform::with_elevation(
  self : Transform,
  elevation : Double,
) -> Transform {
  if elevation == self.elevation || elevation.is_nan() || elevation.is_inf() {
    return self
  }
  make(self.camera, self.width, self.height, self.limits, elevation)
}

///|
/// The same viewport looking through another camera.
pub fn Transform::with_camera(self : Transform, camera : Camera) -> Transform {
  if !finite(camera) {
    return self
  }
  make(
    constrain(camera, self.limits, self.width, self.height),
    self.width,
    self.height,
    self.limits,
    self.elevation,
  )
}

///|
/// The same view under other `limits` (the camera kept to them).
pub fn Transform::with_limits(self : Transform, limits : Limits) -> Transform {
  make(
    constrain(self.camera, limits, self.width, self.height),
    self.width,
    self.height,
    limits,
    self.elevation,
  )
}

///|
/// The same camera on a `width` x `height` viewport, moved if the limits ask.
pub fn Transform::resize(
  self : Transform,
  width : Double,
  height : Double,
) -> Transform {
  if width == self.width && height == self.height {
    return self
  }
  make(
    constrain(self.camera, self.limits, width, height),
    width,
    height,
    self.limits,
    self.elevation,
  )
}

///|
/// World width in CSS pixels at the current zoom.
pub fn Transform::world_size(self : Transform) -> Double {
  TILE_SIZE * @math.pow(2.0, self.camera.zoom)
}

///|
/// The points on the near and far planes (world pixels relative to the center)
/// under the screen point (x, y): near x, y, z, then far x, y, z.
fn Transform::screen_ray(
  self : Transform,
  x : Double,
  y : Double,
) -> (Double, Double, Double, Double, Double, Double) {
  let nx = x / self.width * 2.0 - 1.0
  let ny = 1.0 - y / self.height * 2.0
  let (ax, ay, az, aw) = self.inverse.apply(nx, ny, -1.0, 1.0)
  let (bx, by, bz, bw) = self.inverse.apply(nx, ny, 1.0, 1.0)
  (ax / aw, ay / aw, az / aw, bx / bw, by / bw, bz / bw)
}

///|
/// The ground point (world pixels relative to the center) under the screen
/// point (x, y): where the ray through it meets the map plane. Points above the
/// horizon line take the ground at the line.
fn Transform::ground(
  self : Transform,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let y = @cmp.maximum(y, self.height / 2.0 - self.horizon())
  let (ax, ay, az, bx, by, bz) = self.screen_ray(x, y)
  if az == bz {
    return (0.0, 0.0)
  }
  let t = az / (az - bz)
  (ax + (bx - ax) * t, ay + (by - ay) * t)
}

///|
/// Mercator position under the screen point (x, y), measured in CSS pixels
/// from the viewport's top-left corner (at the horizon for a point above it).
pub fn Transform::screen_to_mercator(
  self : Transform,
  x : Double,
  y : Double,
) -> MercatorCoord {
  let c = self.camera.center.to_mercator()
  let ws = self.world_size()
  let (px, py) = self.ground(x, y)
  { x: c.x + px / ws, y: c.y + py / ws, }
}

///|
/// The camera after a drag from screen point (x0, y0) to (x1, y1): the map
/// point under the pointer follows it.
pub fn Transform::panned(
  self : Transform,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Camera {
  let a = self.screen_to_mercator(x0, y0)
  let b = self.screen_to_mercator(x1, y1)
  let c = self.camera.center.to_mercator()
  let center : MercatorCoord = { x: c.x + a.x - b.x, y: c.y + a.y - b.y, }
  constrain(
    { ..self.camera, center: center.to_lnglat(), },
    self.limits,
    self.width,
    self.height,
  )
}

///|
/// `camera`'s zoom, bearing and pitch, centered so that the map point under
/// screen point (x, y) stays there.
pub fn Transform::keeping(
  self : Transform,
  x : Double,
  y : Double,
  camera : Camera,
) -> Camera {
  let anchor = self.screen_to_mercator(x, y)
  let next = self.with_camera({ ..camera, center: self.camera.center, })
  let moved = next.screen_to_mercator(x, y)
  let c = next.camera.center.to_mercator()
  let center : MercatorCoord = {
    x: c.x + anchor.x - moved.x,
    y: c.y + anchor.y - moved.y,
  }
  constrain(
    { ..next.camera, center: center.to_lnglat(), },
    self.limits,
    self.width,
    self.height,
  )
}

///|
/// The camera at `zoom` that keeps the map point under screen point (x, y) fixed.
pub fn Transform::zoomed_around(
  self : Transform,
  x : Double,
  y : Double,
  zoom : Double,
) -> Camera {
  self.keeping(x, y, { ..self.camera, zoom, })
}

///|
/// Clip-space w of the screen center: points at other depths have w in
/// proportion to their distance from the camera.
pub fn Transform::center_depth(self : Transform) -> Double {
  center_distance(self.height)
}

///|
/// MapLibre's `modelViewProjectionMatrix`: world pixels from the world's
/// top-left corner (x east, y south) and meters above sea level to clip space.
pub fn Transform::world_matrix(self : Transform) -> Mat4 {
  let ws = self.world_size()
  let c = self.camera.center.to_mercator()
  self.view
  .translate(-c.x * ws, -c.y * ws, 0.0)
  .scale(1.0, 1.0, self.pixels_per_meter())
}

///|
/// MapLibre's `projectionMatrix`, `nearZ` and `farZ`: the perspective alone and
/// its near and far planes (CSS pixels from the camera).
pub fn Transform::projection(self : Transform) -> (Mat4, Double, Double) {
  let lift = self.elevation * self.pixels_per_meter()
  let near = self.height / 50.0
  let far = far_distance(self.camera.pitch, self.height, lift)
  (
    Mat4::perspective(FIELD_OF_VIEW, self.width / self.height, near, far),
    near,
    far,
  )
}

///|
/// Maps tile units (`extent` per edge) of `tile` to clip space; `aligned` puts it
/// on the pixel grid as MapLibre draws raster tiles at rest (`alignedProjMatrix`).
pub fn Transform::tile_matrix(
  self : Transform,
  tile : TileId,
  extent : Int32,
  aligned~ : Bool = false,
) -> Mat4 {
  let ws = self.world_size()
  let tiles = (1 << tile.z).to_double()
  let c = self.camera.center.to_mercator()
  let units = self.tile_scale(tile, extent)
  let mut tx = (tile.x.to_double() / tiles - c.x) * ws
  let mut ty = (tile.y.to_double() / tiles - c.y) * ws
  if aligned {
    let (x, y) = (c.x * ws, c.y * ws)
    let x_shift = (self.width.to_int() % 2).to_double() / 2.0
    let y_shift = (self.height.to_int() % 2).to_double() / 2.0
    let b = radians(self.camera.bearing)
    let (cos, sin) = (@math.cos(b), @math.sin(-b))
    let dx = x - x.round() + cos * x_shift + sin * y_shift
    let dy = y - y.round() + cos * y_shift + sin * x_shift
    tx += if dx > 0.5 { dx - 1.0 } else { dx }
    ty += if dy > 0.5 { dy - 1.0 } else { dy }
  }
  // view * translate(tx, ty, 0) * scale(units, units, 1), column by column.
  let v = self.view.m
  let m = FixedArray::make(16, 0.0)
  for r in 0..<4 {
    m[r] = v[r] * units
    m[4 + r] = v[4 + r] * units
    m[8 + r] = v[8 + r]
    m[12 + r] = v[r] * tx + v[4 + r] * ty + v[12 + r]
  }
  { m, }
}

///|
/// CSS pixels per tile unit of `tile` at the center's depth (lines are
/// extruded in tile units with it, so they shrink with distance like the map).
pub fn Transform::tile_scale(
  self : Transform,
  tile : TileId,
  extent : Int32,
) -> Double {
  self.world_size() / (1 << tile.z).to_double() / extent.to_double()
}
