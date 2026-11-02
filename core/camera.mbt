// Camera moves and the screen as MapLibre GL JS 6.16.0 computes them (src/ui/
// camera.ts, src/geo/projection/), BSD-3-Clause, Copyright (c) 2020 MapLibre
// contributors; see NOTICE.

///|
/// A box in longitude and latitude; `west` may exceed `east` across the
/// antimeridian.
pub(all) struct LngLatBounds {
  west : Double
  south : Double
  east : Double
  north : Double
} derive(Debug, Eq)

///|
/// The bounds holding nothing yet (`extend` grows them).
pub fn LngLatBounds::empty() -> LngLatBounds {
  {
    west: @double.infinity,
    south: @double.infinity,
    east: @double.neg_infinity,
    north: @double.neg_infinity,
  }
}

///|
pub fn LngLatBounds::including(self : LngLatBounds, p : LngLat) -> LngLatBounds {
  {
    west: @cmp.minimum(self.west, p.lng),
    south: @cmp.minimum(self.south, p.lat),
    east: @cmp.maximum(self.east, p.lng),
    north: @cmp.maximum(self.north, p.lat),
  }
}

///|
/// Screen point (CSS pixels) of `p` at `elevation` meters. A point behind the
/// camera goes to the edge of the viewport grown by its size on each side, in
/// its direction from the center (MapLibre's `project`).
pub fn Transform::project(
  self : Transform,
  p : LngLat,
  elevation~ : Double = 0.0,
) -> (Double, Double) {
  let c = self.camera.center.to_mercator()
  let m = p.to_mercator()
  let ws = self.world_size()
  let (x, y, _, w) = self.view.apply(
    (m.x - c.x) * ws,
    (m.y - c.y) * ws,
    elevation * self.pixels_per_meter(),
    1.0,
  )
  let cx = self.width / 2.0
  let cy = self.height / 2.0
  // Clip space to pixels before the division by w.
  let px = (x + w) / 2.0 * self.width
  let py = (w - y) / 2.0 * self.height
  if w > 0.0 {
    return (px / w, py / w)
  }
  let dx = px - cx * w
  let dy = if dx == 0.0 && py - cy * w == 0.0 { 1.0 } else { py - cy * w }
  let sx = if dx != 0.0 {
    (cx + self.width) / dx.abs()
  } else {
    @double.infinity
  }
  let sy = if dy != 0.0 {
    (cy + self.height) / dy.abs()
  } else {
    @double.infinity
  }
  let s = @cmp.minimum(sx, sy)
  (cx + dx * s, cy + dy * s)
}

///|
/// Where the ray through screen point (x, y) meets the ground at sea level,
/// in mercator units; above the horizon the ray meets it behind the camera.
fn Transform::ray_ground(
  self : Transform,
  x : Double,
  y : Double,
) -> MercatorCoord {
  let nx = x / self.width * 2.0 - 1.0
  let ny = 1.0 - y / self.height * 2.0
  let (ax, ay, az, aw) = self.inverse.apply(nx, ny, -1.0, 1.0)
  let (bx, by, bz, bw) = self.inverse.apply(nx, ny, 1.0, 1.0)
  let (ax, ay, az) = (ax / aw, ay / aw, az / aw)
  let (bx, by, bz) = (bx / bw, by / bw, bz / bw)
  let t = if az == bz { 0.0 } else { az / (az - bz) }
  let c = self.camera.center.to_mercator()
  let ws = self.world_size()
  { x: c.x + (ax + (bx - ax) * t) / ws, y: c.y + (ay + (by - ay) * t) / ws, }
}

///|
/// The ground point at sea level under screen point (x, y) (MapLibre's
/// `unproject` without terrain; a point above the horizon gives where its ray
/// meets the ground behind the camera, as there).
pub fn Transform::unproject(self : Transform, x : Double, y : Double) -> LngLat {
  self.ray_ground(x, y).to_lnglat()
}

///|
/// The box around the ground at the viewport's corners, its top edge taken at
/// the horizon line when that is on screen (MapLibre's `getBounds`).
pub fn Transform::bounds(self : Transform) -> LngLatBounds {
  let top = @cmp.maximum(0.0, self.height / 2.0 - self.horizon())
  LngLatBounds::empty()
  .including(self.unproject(0.0, top))
  .including(self.unproject(self.width, top))
  .including(self.unproject(self.width, self.height))
  .including(self.unproject(0.0, self.height))
}

///|
/// The camera, as `self`'s but centered so that `p` is at screen point (x, y)
/// (MapLibre's `setLocationAtPoint`), kept to the limits.
pub fn Transform::at_point(
  self : Transform,
  p : LngLat,
  x : Double,
  y : Double,
) -> Camera {
  let a = self.ray_ground(x, y)
  let b = self.ray_ground(self.width / 2.0, self.height / 2.0)
  let m = p.to_mercator()
  let center = ({ x: m.x - (a.x - b.x), y: m.y - (a.y - b.y), } : MercatorCoord).to_lnglat()
  constrain({ ..self.camera, center, }, self.limits, self.width, self.height)
}

///|
/// Space around a box fitted to the screen, in CSS pixels.
pub(all) struct Padding {
  top : Double
  right : Double
  bottom : Double
  left : Double
} derive(Debug, Eq)

///|
pub fn Padding::uniform(p : Double) -> Padding {
  { top: p, right: p, bottom: p, left: p, }
}

///|
fn rotate(x : Double, y : Double, rad : Double) -> (Double, Double) {
  let c = @math.cos(rad)
  let s = @math.sin(rad)
  (c * x - s * y, s * x + c * y)
}

///|
/// The camera showing `b` as large as the viewport less `padding` allows at
/// `bearing`, up to `max_zoom`, shifted by `offset` (MapLibre's `cameraForBounds`,
/// pitch kept). None when the padding leaves no room.
pub fn Transform::camera_for_bounds(
  self : Transform,
  b : LngLatBounds,
  bearing~ : Double = 0.0,
  padding~ : Padding = Padding::uniform(0.0),
  offset~ : (Double, Double) = (0.0, 0.0),
  max_zoom? : Double,
) -> Camera? {
  let max_zoom = max_zoom.unwrap_or(self.limits.max_zoom)
  // `adjustAntiMeridian`: a box across the antimeridian runs past 180°.
  let east = if b.west > b.east { b.east + 360.0 } else { b.east }
  let ws = self.world_size()
  let south = @cmp.maximum(-MAX_LATITUDE, @cmp.minimum(MAX_LATITUDE, b.south))
  let north = @cmp.maximum(-MAX_LATITUDE, @cmp.minimum(MAX_LATITUDE, b.north))
  let nw = ({ lng: b.west, lat: north, } : LngLat).to_mercator()
  let se = ({ lng: east, lat: south, } : LngLat).to_mercator()
  let rad = radians(-bearing)
  let mut min_x = @double.infinity
  let mut min_y = @double.infinity
  let mut max_x = @double.neg_infinity
  let mut max_y = @double.neg_infinity
  for c in [(nw.x, nw.y), (se.x, nw.y), (se.x, se.y), (nw.x, se.y)] {
    let (x, y) = rotate(c.0 * ws, c.1 * ws, rad)
    min_x = @cmp.minimum(min_x, x)
    min_y = @cmp.minimum(min_y, y)
    max_x = @cmp.maximum(max_x, x)
    max_y = @cmp.maximum(max_y, y)
  }
  let available_w = self.width - (padding.left + padding.right)
  let available_h = self.height - (padding.top + padding.bottom)
  let scale_x = available_w / (max_x - min_x)
  let scale_y = available_h / (max_y - min_y)
  guard scale_x >= 0.0 && scale_y >= 0.0 && !(max_x - min_x).is_inf() else {
    return None
  }
  let scale = @math.pow(2.0, self.camera.zoom)
  let zoom = @cmp.minimum(
    @math.log2(scale * @cmp.minimum(scale_x, scale_y)),
    max_zoom,
  )
  let (px, py) = rotate(
    (padding.left - padding.right) / 2.0,
    (padding.top - padding.bottom) / 2.0,
    radians(bearing),
  )
  let k = scale / @math.pow(2.0, zoom)
  let ox = (offset.0 + px) * k
  let oy = (offset.1 + py) * k
  let center = (
    {
      x: ((nw.x + se.x) * ws / 2.0 - ox) / ws,
      y: ((nw.y + se.y) * ws / 2.0 - oy) / ws,
    } : MercatorCoord).to_lnglat()
  Some({
    ..self.camera,
    center: { lng: wrap180(center.lng), lat: center.lat, },
    zoom,
    bearing,
  })
}

///|
/// How much farther than the center the screen's top-left corner is
/// (MapLibre's `maxPitchScaleFactor`): queries grow their padding by it.
pub fn Transform::max_pitch_scale_factor(self : Transform) -> Double {
  let m = self.screen_to_mercator(0.0, 0.0)
  let c = self.camera.center.to_mercator()
  let ws = self.world_size()
  let (_, _, _, w) = self.view.apply(
    (m.x - c.x) * ws,
    (m.y - c.y) * ws,
    0.0,
    1.0,
  )
  w / self.center_depth()
}
