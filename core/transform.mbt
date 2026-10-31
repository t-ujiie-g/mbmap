///|
/// CSS pixels per tile edge at integer zooms, as in MapLibre: the world is
/// `TILE_SIZE * 2^zoom` pixels wide.
pub const TILE_SIZE : Double = 512.0

///|
/// Tile units per tile edge in packed tiles: workers rescale every layer to it.
pub const TILE_EXTENT : Int32 = 4096

///|
/// Highest pitch in degrees. Up to here the horizon stays off screen (pitch
/// plus half the field of view is below 90°), so every screen point maps to
/// the ground.
pub const MAX_PITCH : Double = 60.0

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
/// A camera applied to a viewport of `width` x `height` CSS pixels. Zoom is
/// clamped to `[min_zoom, max_zoom]`, latitude to `MAX_LATITUDE` and pitch to
/// `[0, MAX_PITCH]`; longitude and bearing wrap. A camera with a non-finite
/// value is ignored (`new` falls back to 0, 0, zoom 0). Positions are handled
/// in world pixels relative to the center, so precision holds at every zoom.
pub struct Transform {
  camera : Camera
  width : Double
  height : Double
  min_zoom : Double
  max_zoom : Double
  priv view : Mat4
  priv inverse : Mat4
}

///|
pub fn Transform::new(
  camera : Camera,
  width : Double,
  height : Double,
  min_zoom~ : Double = 0.0,
  max_zoom~ : Double = 22.0,
) -> Transform {
  let camera = if finite(camera) {
    camera
  } else {
    { center: { lng: 0.0, lat: 0.0, }, zoom: 0.0, bearing: 0.0, pitch: 0.0, }
  }
  make(constrain(camera, min_zoom, max_zoom), width, height, min_zoom, max_zoom)
}

///|
fn make(
  camera : Camera,
  width : Double,
  height : Double,
  min_zoom : Double,
  max_zoom : Double,
) -> Transform {
  let view = view_projection(camera, width, height)
  {
    camera,
    width,
    height,
    min_zoom,
    max_zoom,
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
/// World pixels relative to the center (y south) to clip space, as MapLibre
/// builds it: perspective, y flipped, pulled back by the camera distance,
/// pitched, then rotated by the bearing.
fn view_projection(camera : Camera, width : Double, height : Double) -> Mat4 {
  let d = center_distance(height)
  let pitch = radians(camera.pitch)
  let half_fov = FIELD_OF_VIEW / 2.0
  // Far enough for the top edge of the screen, which looks farthest away.
  let top = @math.sin(half_fov) *
    d /
    @math.sin(@math.PI / 2.0 - pitch - half_fov)
  let far = (@math.sin(pitch) * top + d) * 1.01
  Mat4::perspective(FIELD_OF_VIEW, width / height, height / 50.0, far)
  .scale(1.0, -1.0, 1.0)
  .translate(0.0, 0.0, -d)
  .rotate_x(pitch)
  .rotate_z(-radians(camera.bearing))
}

///|
fn constrain(camera : Camera, min_zoom : Double, max_zoom : Double) -> Camera {
  let zoom = @cmp.maximum(min_zoom, @cmp.minimum(max_zoom, camera.zoom))
  let lat = @cmp.maximum(
    -MAX_LATITUDE,
    @cmp.minimum(MAX_LATITUDE, camera.center.lat),
  )
  {
    center: { lng: wrap180(camera.center.lng), lat, },
    zoom,
    bearing: wrap180(camera.bearing),
    pitch: @cmp.maximum(0.0, @cmp.minimum(MAX_PITCH, camera.pitch)),
  }
}

///|
/// `v` in [-180, 180), so longitudes and bearings stay bounded.
fn wrap180(v : Double) -> Double {
  v - 360.0 * ((v + 180.0) / 360.0).floor()
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
    constrain(camera, self.min_zoom, self.max_zoom),
    self.width,
    self.height,
    self.min_zoom,
    self.max_zoom,
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
  make(self.camera, width, height, self.min_zoom, self.max_zoom)
}

///|
/// World width in CSS pixels at the current zoom.
pub fn Transform::world_size(self : Transform) -> Double {
  TILE_SIZE * @math.pow(2.0, self.camera.zoom)
}

///|
/// The ground point (world pixels relative to the center) under the screen
/// point (x, y): where the ray through it meets the map plane.
fn Transform::ground(
  self : Transform,
  x : Double,
  y : Double,
) -> (Double, Double) {
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
/// from the viewport's top-left corner.
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
    self.min_zoom,
    self.max_zoom,
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
    self.min_zoom,
    self.max_zoom,
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
/// Integer tile zoom for a source with tiles of `TILE_SIZE` pixels, limited
/// to the source's zoom range (higher camera zooms overzoom `max_tile_zoom`).
pub fn Transform::tile_zoom(
  self : Transform,
  min_tile_zoom : Int32,
  max_tile_zoom : Int32,
) -> Int32 {
  let z = self.camera.zoom.floor().to_int()
  @cmp.maximum(min_tile_zoom, @cmp.minimum(max_tile_zoom, z))
}

///|
/// How far from the camera tiles stay at the full tile zoom, in camera
/// distances; each doubling beyond it drops one zoom level. 1.5 keeps every
/// tile of an unpitched view with an aspect ratio up to about 3 at full zoom.
const LOD_DISTANCE : Double = 1.5

///|
/// Tiles that intersect the view, from `max_z` near the camera down to
/// `min_z` far from it (with pitch, distant ground is drawn from lower
/// zooms), nearest to the center first. The tiles never overlap.
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
    let split = tile.z < min_z ||
      (
        tile.z < max_z &&
        dist < LOD_DISTANCE * d * (1 << (max_z - tile.z - 1)).to_double()
      )
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
pub fn Transform::tile_matrix(
  self : Transform,
  tile : TileId,
  extent : Int32,
) -> Mat4 {
  let ws = self.world_size()
  let tiles = (1 << tile.z).to_double()
  let c = self.camera.center.to_mercator()
  let units = self.tile_scale(tile, extent)
  let tx = (tile.x.to_double() / tiles - c.x) * ws
  let ty = (tile.y.to_double() / tiles - c.y) * ws
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
