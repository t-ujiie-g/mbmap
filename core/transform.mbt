///|
/// CSS pixels per tile edge at integer zooms, as in MapLibre: the world is
/// `TILE_SIZE * 2^zoom` pixels wide.
pub const TILE_SIZE : Double = 512.0

///|
/// Tile units per tile edge in packed tiles: workers rescale every layer to it.
pub const TILE_EXTENT : Int32 = 4096

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
pub(all) struct Camera {
  center : LngLat
  zoom : Double
  bearing : Double
  pitch : Double
} derive(Debug, Eq)

///|
/// What a camera may do: zoom and pitch ranges and, if set, `bounds` the
/// view may not leave (MapLibre's `maxBounds`).
pub(all) struct Limits {
  min_zoom : Double
  max_zoom : Double
  min_pitch : Double
  max_pitch : Double
  bounds : LngLatBounds?
} derive(Debug, Eq)

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
/// A camera on a `width` x `height` CSS-pixel viewport, kept to `limits` and to
/// the world between `MAX_LATITUDE` north and south as MapLibre keeps it;
/// non-finite cameras are ignored. Positions are world pixels relative to the
/// center, so precision holds. `elevation` (meters) lifts the center onto
/// terrain; the camera orbits it.
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
fn radians(degrees : Double) -> Double {
  degrees * @math.PI / 180.0
}

///|
/// Distance from the camera to the center, in CSS pixels.
fn center_distance(height : Double) -> Double {
  height / 2.0 / @math.tan(FIELD_OF_VIEW / 2.0)
}

///|
/// World pixels relative to the center (y south, z up) to clip space, as
/// MapLibre builds it: perspective, y flipped, pulled back by the camera
/// distance, pitched, rotated by the bearing, and lowered by `lift` world
/// pixels so the center sits on the terrain.
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
/// Depth (CSS pixels along the view axis) of the farthest ground drawn: the
/// top edge of the screen or the horizon line, whichever is nearer, on the
/// plane through sea level, or through the center when terrain below sea level
/// lifts it (`lift` world pixels; MapLibre's `_calculateNearFarZ`).
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
/// `camera` kept to `limits` on a `width` x `height` viewport: zoom and pitch
/// clamped, bearing and longitude wrapped to (-180, 180], and the center moved
/// (or the zoom raised) so the view stays between the latitude limits and
/// inside `bounds` (MapLibre's `defaultConstrain`, map padding left out).
fn constrain(
  camera : Camera,
  limits : Limits,
  width : Double,
  height : Double,
) -> Camera {
  let zoom = @cmp.maximum(
    limits.min_zoom,
    @cmp.minimum(limits.max_zoom, camera.zoom),
  )
  let camera = {
    ..camera,
    zoom,
    bearing: wrap180(camera.bearing),
    pitch: @cmp.maximum(
      limits.min_pitch,
      @cmp.minimum(limits.max_pitch, camera.pitch),
    ),
  }
  // MapLibre sets the zoom before the center and constrains each time: the
  // zoom rises until the ranges fill the view, then the center is kept in.
  let clamp = (z : Double) => {
    @cmp.maximum(limits.min_zoom, @cmp.minimum(limits.max_zoom, z))
  }
  let mut zoom = zoom
  for _ in 0..<3 {
    let (_, z) = constrain_center(camera.center, zoom, limits, width, height)
    if clamp(z) == zoom {
      break
    }
    zoom = clamp(z)
  }
  let (center, _) = constrain_center(camera.center, zoom, limits, width, height)
  { ..camera, center: { lng: wrap180(center.lng), lat: center.lat, }, zoom, }
}

///|
/// `camera` after one pass of MapLibre's constraint (`applyConstrain`), as
/// its moves take their end point: a zoom raised to fit a range centers that
/// range and leaves the other axis alone.
fn constrain_once(
  camera : Camera,
  limits : Limits,
  width : Double,
  height : Double,
) -> Camera {
  let zoom = @cmp.maximum(
    limits.min_zoom,
    @cmp.minimum(limits.max_zoom, camera.zoom),
  )
  let (center, zoom) = constrain_center(
    camera.center,
    zoom,
    limits,
    width,
    height,
  )
  { ..camera, center: { lng: wrap180(center.lng), lat: center.lat, }, zoom, }
}

///|
/// The latitude limit MapLibre keeps the view to (`MAX_VALID_LATITUDE`,
/// `MAX_LATITUDE` rounded).
const MAX_VALID_LATITUDE : Double = 85.051129

///|
fn constrain_center(
  center : LngLat,
  zoom : Double,
  limits : Limits,
  width : Double,
  height : Double,
) -> (LngLat, Double) {
  let world = TILE_SIZE * @math.pow(2.0, zoom)
  let (south, north, lng_range) = match limits.bounds {
    Some(b) => (b.south, b.north, Some((b.west, b.east)))
    None => (-MAX_VALID_LATITUDE, MAX_VALID_LATITUDE, None)
  }
  let min_y = mercator_y_from_lat(north) * world
  let max_y = mercator_y_from_lat(south) * world
  let scale_y = if max_y - min_y < height {
    height / (max_y - min_y)
  } else {
    0.0
  }
  let (min_x, max_x, scale_x) = match lng_range {
    Some((west, east)) => {
      let min_x = wrap_range(mercator_x_from_lng(west) * world, 0.0, world)
      let max_x = wrap_range(mercator_x_from_lng(east) * world, 0.0, world)
      let max_x = if max_x < min_x { max_x + world } else { max_x }
      (
        min_x,
        max_x,
        if max_x - min_x < width {
          width / (max_x - min_x)
        } else {
          0.0
        },
      )
    }
    None => (0.0, world, 0.0)
  }
  let x = mercator_x_from_lng(center.lng) * world
  let y = mercator_y_from_lat(center.lat) * world
  let scale = @cmp.maximum(scale_x, scale_y)
  if scale > 0.0 {
    let m : MercatorCoord = {
      x: (if scale_x > 0.0 { (max_x + min_x) / 2.0 } else { x }) / world,
      y: (if scale_y > 0.0 { (max_y + min_y) / 2.0 } else { y }) / world,
    }
    let c = m.to_lnglat()
    return ({ lng: wrap180(c.lng), lat: c.lat, }, zoom + @math.log2(scale))
  }
  let mut new_y = y
  if y - height / 2.0 < min_y {
    new_y = min_y + height / 2.0
  }
  if y + height / 2.0 > max_y {
    new_y = max_y - height / 2.0
  }
  let mut new_x = x
  if lng_range is Some(_) {
    let mid = (min_x + max_x) / 2.0
    let wrapped = wrap_range(x, mid - world / 2.0, mid + world / 2.0)
    if wrapped - width / 2.0 < min_x {
      new_x = min_x + width / 2.0
    }
    if wrapped + width / 2.0 > max_x {
      new_x = max_x - width / 2.0
    }
  }
  if new_x == x && new_y == y {
    return (center, zoom)
  }
  let c = ({ x: new_x / world, y: new_y / world, } : MercatorCoord).to_lnglat()
  ({ lng: wrap180(c.lng), lat: c.lat, }, zoom)
}

///|
/// `v` in (`min`, `max`] (MapLibre's `wrap`).
fn wrap_range(v : Double, min : Double, max : Double) -> Double {
  // Values already in range stay exact (the modulo below would round them).
  if v > min && v <= max {
    return v
  }
  let d = max - min
  let w = ((v - min) % d + d) % d + min
  if w == min {
    max
  } else {
    w
  }
}

///|
/// `v` in (-180, 180], so longitudes and bearings stay bounded.
fn wrap180(v : Double) -> Double {
  wrap_range(v, -180.0, 180.0)
}

///|
fn finite(camera : Camera) -> Bool {
  let ok = (x : Double) => !x.is_nan() && !x.is_inf()
  ok(camera.zoom) &&
  ok(camera.center.lng) &&
  ok(camera.center.lat) &&
  ok(camera.bearing) &&
  ok(camera.pitch)
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
/// The ground point (world pixels relative to the center) under the screen
/// point (x, y): where the ray through it meets the map plane. Points above the
/// horizon line take the ground at the line.
fn Transform::ground(
  self : Transform,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let y = @cmp.maximum(y, self.height / 2.0 - self.horizon())
  let nx = x / self.width * 2.0 - 1.0
  let ny = 1.0 - y / self.height * 2.0
  let (ax, ay, az, aw) = self.inverse.apply(nx, ny, -1.0, 1.0)
  let (bx, by, bz, bw) = self.inverse.apply(nx, ny, 1.0, 1.0)
  let (ax, ay, az) = (ax / aw, ay / aw, az / aw)
  let (bx, by, bz) = (bx / bw, by / bw, bz / bw)
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
/// Screen point (CSS pixels) of a mercator position.
pub fn Transform::mercator_to_screen(
  self : Transform,
  m : MercatorCoord,
) -> (Double, Double) {
  let c = self.camera.center.to_mercator()
  let ws = self.world_size()
  let (x, y, _, w) = self.view.apply(
    (m.x - c.x) * ws,
    (m.y - c.y) * ws,
    0.0,
    1.0,
  )
  ((x / w + 1.0) / 2.0 * self.width, (1.0 - y / w) / 2.0 * self.height)
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
/// How many zoom levels deeper tiles of `tile_size` pixels (a power of two up to
/// `TILE_SIZE`) are than `TILE_SIZE` ones at the same camera zoom.
pub fn zoom_shift(tile_size : Int32) -> Int32 {
  let mut shift = 0
  while shift < 8 && tile_size << shift < TILE_SIZE.to_int() {
    shift += 1
  }
  shift
}

///|
/// Integer tile zoom for a source with tiles of `tile_size` pixels (a power of
/// two up to `TILE_SIZE`: 256-pixel tiles take one zoom more), limited to the
/// source's zoom range (higher camera zooms overzoom `max_tile_zoom`).
pub fn Transform::tile_zoom(
  self : Transform,
  min_tile_zoom : Int32,
  max_tile_zoom : Int32,
  tile_size~ : Int32 = 512,
) -> Int32 {
  let z = self.camera.zoom.floor().to_int() + zoom_shift(tile_size)
  @cmp.maximum(min_tile_zoom, @cmp.minimum(max_tile_zoom, z))
}

///|
/// How far from the camera tiles stay at the full tile zoom, in camera
/// distances; each doubling beyond it drops one zoom level. 1.5 keeps every
/// tile of an unpitched view with an aspect ratio up to about 3 at full zoom.
const LOD_DISTANCE : Double = 1.5

///|
/// Zoom levels below a source's `min_z` that distant ground may want and still
/// be drawn from `min_z` tiles; farther ground is left to the fog.
const MIN_ZOOM_SLACK : Int32 = 2

///|
/// Tiles that intersect the view, from `max_z` near the camera down to
/// `min_z` far from it (with pitch, distant ground is drawn from lower
/// zooms), nearest to the center first. The tiles never overlap. Ground that
/// wants a zoom more than `MIN_ZOOM_SLACK` below `min_z` gets no tiles, as in
/// MapLibre (which drops anything below `min_z`).
pub fn Transform::covering_tiles(
  self : Transform,
  min_z : Int32,
  max_z : Int32,
) -> Array[TileId] {
  let ws = self.world_size()
  let c = self.camera.center.to_mercator()
  // The view's footprint on the ground, in mercator units.
  let footprint = [
    self.screen_to_mercator(0.0, 0.0),
    self.screen_to_mercator(self.width, 0.0),
    self.screen_to_mercator(self.width, self.height),
    self.screen_to_mercator(0.0, self.height),
  ]
  // The camera's ground position and height, in world pixels from the center.
  let d = center_distance(self.height)
  let pitch = radians(self.camera.pitch)
  let bearing = radians(self.camera.bearing)
  let behind = d * @math.sin(pitch)
  let cam_x = -@math.sin(bearing) * behind
  let cam_y = @math.cos(bearing) * behind
  let cam_z = d * @math.cos(pitch)
  let tiles : Array[(Double, TileId)] = []
  let stack : Array[TileId] = [{ z: 0, x: 0, y: 0, }]
  while stack.pop() is Some(tile) {
    let b = tile.mercator_bounds()
    if !overlaps(footprint, b) {
      continue
    }
    // Distance from the camera to the tile's nearest ground point.
    let nx = (
        @cmp.maximum(b.min_x, @cmp.minimum(b.max_x, c.x + cam_x / ws)) - c.x
      ) *
      ws -
      cam_x
    let ny = (
        @cmp.maximum(b.min_y, @cmp.minimum(b.max_y, c.y + cam_y / ws)) - c.y
      ) *
      ws -
      cam_y
    let dist = (nx * nx + ny * ny + cam_z * cam_z).sqrt()
    let near = (levels : Int32) => {
      dist < LOD_DISTANCE * d * @math.pow(2.0, levels.to_double())
    }
    let split = if tile.z < min_z {
      if !near(max_z - min_z + MIN_ZOOM_SLACK) {
        continue
      }
      true
    } else {
      tile.z < max_z && near(max_z - tile.z - 1)
    }
    if split && tile.children() is Some(kids) {
      for k in kids {
        stack.push(k)
      }
    } else {
      let dx = (b.min_x + b.max_x) / 2.0 - c.x
      let dy = (b.min_y + b.max_y) / 2.0 - c.y
      tiles.push((dx * dx + dy * dy, tile))
    }
  }
  tiles.sort_by((a, b) => a.0.compare(b.0))
  tiles.map(t => t.1)
}

///|
/// Whether the convex polygon `poly` and the box `b` intersect: no separating
/// axis among the box's axes and the polygon's edge normals.
fn overlaps(poly : Array[MercatorCoord], b : BBox) -> Bool {
  let n = poly.length()
  // Box axes: the polygon's extent against the box's.
  let mut x0 = poly[0].x
  let mut x1 = x0
  let mut y0 = poly[0].y
  let mut y1 = y0
  for p in poly {
    x0 = @cmp.minimum(x0, p.x)
    x1 = @cmp.maximum(x1, p.x)
    y0 = @cmp.minimum(y0, p.y)
    y1 = @cmp.maximum(y1, p.y)
  }
  if x1 < b.min_x || x0 > b.max_x || y1 < b.min_y || y0 > b.max_y {
    return false
  }
  // Edge normals: the box lies wholly outside an edge if even its corner
  // farthest along the inward normal is outside. `poly` turns one way, so
  // the sign of `turn` says which side is inside.
  let turn = (poly[1].x - poly[0].x) * (poly[2].y - poly[1].y) -
    (poly[1].y - poly[0].y) * (poly[2].x - poly[1].x)
  for i in 0..<n {
    let p = poly[i]
    let q = poly[(i + 1) % n]
    // Inward normal of edge p -> q.
    let (nx, ny) = if turn > 0.0 {
      (p.y - q.y, q.x - p.x)
    } else {
      (q.y - p.y, p.x - q.x)
    }
    let cx = if nx > 0.0 { b.max_x } else { b.min_x }
    let cy = if ny > 0.0 { b.max_y } else { b.min_y }
    if (cx - p.x) * nx + (cy - p.y) * ny < 0.0 {
      return false
    }
  }
  true
}

///|
/// Clip-space w of the screen center: points at other depths have w in
/// proportion to their distance from the camera.
pub fn Transform::center_depth(self : Transform) -> Double {
  center_distance(self.height)
}

///|
/// Maps tile units (`extent` per tile edge) of `tile` to clip space.
/// `aligned` puts it on the pixel grid as MapLibre draws raster tiles at rest
/// (its `alignedProjMatrix`): the center's fractional world pixel, and half a
/// pixel for an odd viewport size, turned with the bearing, are taken out.
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
    let b = self.camera.bearing * @math.PI / 180.0
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
