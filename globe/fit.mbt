// MapLibre GL JS 6.16.0's `cameraForBoxAndBearing` on the globe and the map-control helpers
// (src/geo/projection/vertical_perspective_camera_helper.ts, globe_utils.ts, mercator_camera_helper.ts,
// src/ui/handler_manager.ts), BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.

///|
/// The camera showing `b` as large as the viewport less `padding` allows at
/// `bearing`, up to `max_zoom`, shifted by `offset` (MapLibre's
/// `cameraForBounds`; pitch kept). None when it does not fit.
pub fn Globe::camera_for_bounds(
  self : Globe,
  b : @core.LngLatBounds,
  bearing~ : Double = 0.0,
  padding~ : @core.Padding = @core.Padding::uniform(0.0),
  offset~ : (Double, Double) = (0.0, 0.0),
  max_zoom? : Double,
) -> @core.Camera? {
  let max_zoom = max_zoom.unwrap_or(self.limits.max_zoom)
  guard @core.fit_box(
      b,
      self.zoom,
      self.width,
      self.height,
      bearing~,
      padding~,
      offset~,
      max_zoom~,
    )
    is Some((center, zoom)) else {
    return None
  }
  let camera = self.camera()
  if !self.is_globe() {
    return Some({ ..camera, center, zoom, bearing, })
  }
  let x_left = padding.left / self.width * 2.0 - 1.0
  let x_right = (self.width - padding.right) / self.width * 2.0 - 1.0
  let y_top = padding.top / self.height * -2.0 + 1.0
  let y_bottom = (self.height - padding.bottom) / self.height * -2.0 + 1.0
  let flip = angle_difference(b.west, b.east) < 0.0
  let west = if flip { b.east } else { b.west }
  let east = if flip { b.west } else { b.east }
  let north = @cmp.maximum(b.north, b.south)
  let south = @cmp.minimum(b.north, b.south)
  let mid_lng = west + angle_difference(west, east) * 0.5
  let mid_lat = north + angle_difference(north, south) * 0.5
  let cloned = self.copy()
  cloned.set_center(center)
  cloned.set_bearing(bearing)
  cloned.set_pitch(0.0)
  cloned.set_zoom(zoom)
  let m = cloned.globe_matrix()
  let to_center = surface_vector(center)
  let mut smallest = @double.infinity
  for
    p in [
      (b.west, b.north),
      (b.east, b.north),
      (b.west, b.south),
      (b.east, b.south),
      (east, mid_lat),
      (west, mid_lat),
      (mid_lng, north),
      (mid_lng, south),
    ] {
    let v = surface_vector({ lng: p.0, lat: p.1, })
    if x_left < 0.0 {
      smallest = lesser(smallest, solve_scale(v, to_center, m, true, x_left))
    }
    if x_right > 0.0 {
      smallest = lesser(smallest, solve_scale(v, to_center, m, true, x_right))
    }
    if y_top > 0.0 {
      smallest = lesser(smallest, solve_scale(v, to_center, m, false, y_top))
    }
    if y_bottom < 0.0 {
      smallest = lesser(smallest, solve_scale(v, to_center, m, false, y_bottom))
    }
  }
  if smallest.is_inf() || smallest.is_nan() || smallest == 0.0 {
    return None
  }
  Some({
    ..camera,
    center,
    zoom: @cmp.minimum(cloned.zoom + scale_zoom(smallest), max_zoom),
    bearing,
  })
}

///|
fn lesser(old : Double, new : Double?) -> Double {
  match new {
    Some(n) if n >= 0.0 && n < old => n
    _ => old
  }
}

///|
/// The scale of the globe that puts `v` at clip coordinate `k` along x (or
/// y) under `m` (`solveVectorScale`).
fn solve_scale(
  v : Vec3,
  to_center : Vec3,
  m : @core.Mat4,
  along_x : Bool,
  k : Double,
) -> Double? {
  let a = m.m
  let r = if along_x { 0 } else { 1 }
  let (c0, c1, c2, c3) = (a[r], a[4 + r], a[8 + r], a[12 + r])
  let (z0, z1, z2, z3) = (a[3], a[7], a[11], a[15])
  let v_xy = v.x * c0 + v.y * c1 + v.z * c2
  let v_z = v.x * z0 + v.y * z1 + v.z * z2
  let c_xy = to_center.x * c0 + to_center.y * c1 + to_center.z * c2
  let c_z = to_center.x * z0 + to_center.y * z1 + to_center.z * z2
  let t = (c_xy + c3 - k * c_z - k * z3) / (c_xy - v_xy - k * c_z + k * v_z)
  if c_xy + k * v_z == v_xy + k * c_z ||
    z3 * (v_xy - c_xy) + c3 * (c_z - v_z) + v_xy * c_z == c_xy * v_z {
    return None
  }
  Some(t)
}

///|
/// A gesture's frame (MapLibre's handler manager without terrain): the map
/// turned by `bearing` and `pitch` degrees and zoomed by `zoom` about screen
/// point (x, y), and the place under it dragged by `pan` pixels.
pub fn Globe::apply_controls(
  self : Globe,
  x : Double,
  y : Double,
  pan~ : (Double, Double) = (0.0, 0.0),
  zoom~ : Double = 0.0,
  bearing~ : Double = 0.0,
  pitch~ : Double = 0.0,
) -> Unit {
  let (cx, cy) = (self.width / 2.0, self.height / 2.0)
  if self.is_globe() {
    self.globe_rotate_zoom(x, y, zoom, bearing, pitch)
    if pan != (0.0, 0.0) {
      let (px, py) = if self.on_surface(x, y) { (x, y) } else { (cx, cy) }
      self.versor_pan(px, py, pan)
    }
    return
  }
  let near_center = (x - cx) * (x - cx) + (y - cy) * (y - cy) < 0.01
  let pre = if near_center {
    self.center
  } else {
    self.unproject(x - pan.0, y - pan.1)
  }
  if bearing != 0.0 {
    self.set_bearing(self.camera().bearing + bearing)
  }
  if pitch != 0.0 {
    self.set_pitch(self.camera().pitch + pitch)
  }
  if zoom != 0.0 {
    self.set_zoom(self.zoom + zoom)
  }
  if !self.on_surface(x, y) {
    if pan != (0.0, 0.0) {
      self.set_center(self.unproject(cx - pan.0, cy - pan.1))
    }
  } else if !near_center {
    self.set_location_at_point(pre, x, y)
  }
}

///|
const RAY_SURFACE_DISTANCE_FOR_SLOWING_START : Double = 0.3

///|
const SLOWING_MULTIPLIER : Double = 0.5

///|
const INTERPOLATE_TO_HEURISTIC_START_LNG : Double = 45.0

///|
const INTERPOLATE_TO_HEURISTIC_END_LNG : Double = 85.0

///|
const INTERPOLATE_TO_HEURISTIC_EXPONENT : Double = 0.25

///|
const INTERPOLATE_TO_HEURISTIC_START_HORIZON : Double = 0.95

///|
const INTERPOLATE_TO_HEURISTIC_END_HORIZON : Double = 0.999

///|
const SLOWING_RADIUS_START : Double = 0.9

///|
const SLOWING_RADIUS_STOP : Double = 0.5

///|
const SLOWING_RADIUS_SLOW_FACTOR : Double = 0.25

///|
/// `handleMapControlsRollPitchBearingZoom` on the globe: the zoom slows
/// toward the horizon and moves the center toward (x, y) by a heuristic.
fn Globe::globe_rotate_zoom(
  self : Globe,
  x : Double,
  y : Double,
  zoom : Double,
  bearing : Double,
  pitch : Double,
) -> Unit {
  let loc = self.unproject(x, y)
  if bearing != 0.0 {
    self.set_bearing(self.camera().bearing + bearing)
  }
  if pitch != 0.0 {
    self.set_pitch(self.camera().pitch + pitch)
  }
  let old = self.zoom
  if zoom != 0.0 {
    self.set_zoom(self.zoom + zoom)
  }
  let actual = self.zoom - old
  if actual == 0.0 {
    return
  }
  let d_lng_raw = angle_difference(self.center.lng, loc.lng)
  let d_lng = d_lng_raw / ((d_lng_raw / 180.0).abs() + 1.0)
  let d_lat = angle_difference(self.center.lat, loc.lat)
  let dir = self.ray_direction(x, y)
  let origin = self.camera_position()
  let to_closest = origin.dot(dir) * -1.0
  let ray_distance = origin.add(dir.scale(to_closest)).length()
  let distance_factor = @math.exp(
    -@cmp.maximum(
      ray_distance - 1.0 - RAY_SURFACE_DISTANCE_FOR_SLOWING_START,
      0.0,
    ) *
    SLOWING_MULTIPLIER,
  )
  let horizon_factor = remap_saturate(
    ray_distance,
    INTERPOLATE_TO_HEURISTIC_START_HORIZON,
    INTERPOLATE_TO_HEURISTIC_END_HORIZON,
    0.0,
    1.0,
  )
  let radius = globe_radius(self.world_size(), self.center.lat) /
    @cmp.minimum(self.width, self.height)
  let radius_factor = remap_saturate(
    radius,
    SLOWING_RADIUS_START,
    SLOWING_RADIUS_STOP,
    1.0,
    SLOWING_RADIUS_SLOW_FACTOR,
  )
  let slowing = @cmp.minimum(
    distance_factor,
    lerp(1.0, radius_factor, horizon_factor),
  )
  let factor = (1.0 - zoom_scale(-actual)) * slowing
  let old_lat = self.center.lat
  let old_zoom = self.zoom
  let heuristic : @core.LngLat = {
    lng: self.center.lng + d_lng * factor,
    lat: clamp(self.center.lat + d_lat * factor, -90.0, 90.0),
  }
  self.set_location_at_point(loc, x, y)
  let exact = self.center
  let lng_factor = remap_saturate(
    d_lng_raw.abs(),
    INTERPOLATE_TO_HEURISTIC_START_LNG,
    INTERPOLATE_TO_HEURISTIC_END_LNG,
    0.0,
    1.0,
  )
  let heuristic_factor = @math.pow(
    @cmp.maximum(lng_factor, horizon_factor),
    INTERPOLATE_TO_HEURISTIC_EXPONENT,
  )
  let d_lng = angle_difference(exact.lng, heuristic.lng)
  let d_lat = angle_difference(exact.lat, heuristic.lat)
  self.set_center(
    wrapped({
      lng: exact.lng + d_lng * heuristic_factor,
      lat: clamp(exact.lat + d_lat * heuristic_factor, -90.0, 90.0),
    }),
  )
  self.set_zoom(old_zoom + zoom_adjustment(old_lat, self.center.lat))
}

///|
const PAN_FALLOFF_BAND : Double = 0.1

///|
const DIAL_MIN_RADIUS_PIXELS : Double = 20.0

///|
const PAN_MAX_ANGLE : Double = 0.98

///|
/// The place a pan grabs at screen point (x, y): past the horizon's falloff
/// band the grab slides along the sphere instead of jumping (`panSurfaceLocation`).
fn Globe::pan_surface(self : Globe, x : Double, y : Double) -> @core.LngLat {
  let origin = self.camera_position()
  let distance = origin.length()
  if distance <= 1.0 {
    return self.unproject(x, y)
  }
  let u = origin.normalize()
  let dir = self.ray_direction(x, y)
  let c = -dir.dot(u)
  let lateral = dir.add_scaled(u, c)
  let s = lateral.length()
  if s < 0.000000001 {
    return self.unproject(x, y)
  }
  let angle = @math.atan2(s, c)
  let horizon = @math.asin(1.0 / distance)
  let handover = horizon * (1.0 - PAN_FALLOFF_BAND)
  if angle < handover {
    return self.unproject(x, y)
  }
  let max_angle = @math.PI * PAN_MAX_ANGLE
  let sin_handover = distance * @math.sin(handover)
  let at_handover = @math.asin(clamp(sin_handover, -1.0, 1.0)) - handover
  let slope = distance *
    @math.cos(handover) /
    @cmp.maximum(1.0 - sin_handover * sin_handover, 1.0e-12).sqrt() -
    1.0
  let room = max_angle - at_handover
  let excess = angle - handover
  let target = at_handover + room * (slope * excess) / (room + slope * excess)
  let e = lateral.scale(1.0 / s)
  let t = clamp(target, 0.0, max_angle)
  surface_point(u.scale(@math.cos(t)).add_scaled(e, @math.sin(t)).normalize())
}

///|
/// Rotates the globe so the place grabbed `pan` pixels before screen point
/// (x, y) comes under it, north kept up (`versorSetLocationAtPoint` with a
/// fixed bearing).
fn Globe::versor_pan(
  self : Globe,
  x : Double,
  y : Double,
  pan : (Double, Double),
) -> Unit {
  let at_point = self.pan_surface(x, y)
  let source = self.pan_surface(x - pan.0, y - pan.1)
  let current = surface_vector(at_point)
  let target = surface_vector(source)
  let q = Quat::from_euler(
    -self.center.lng,
    -self.center.lat,
    self.camera().bearing,
  )
  let w = target.cross(current)
  let l = w.dot(w).sqrt()
  let t = @math.acos(clamp(target.dot(current), -1.0, 1.0)) / 2.0
  let s = @math.sin(t)
  let delta : Quat = if l != 0.0 {
    { x: w.y / l * s, y: -w.x / l * s, z: w.z / l * s, w: @math.cos(t), }
  } else {
    { x: 0.0, y: 0.0, z: 0.0, w: 1.0, }
  }
  let r = q.mul(delta)
  let new_lng = -@math.atan2(
      2.0 * (r.w * r.x + r.y * r.z),
      1.0 - 2.0 * (r.x * r.x + r.y * r.y),
    ) *
    180.0 /
    @math.PI
  let new_lat = -@math.asin(clamp(2.0 * (r.w * r.y - r.z * r.x), -1.0, 1.0)) *
    180.0 /
    @math.PI
  let new_bearing = @math.atan2(
      2.0 * (r.w * r.z + r.x * r.y),
      1.0 - 2.0 * (r.y * r.y + r.z * r.z),
    ) *
    180.0 /
    @math.PI
  let old_lat = self.center.lat
  let old_zoom = self.zoom
  let final_lat = if angle_difference(self.camera().bearing, new_bearing).abs() <=
    90.0 {
    new_lat
  } else if new_lat > 0.0 {
    90.0
  } else {
    -90.0
  }
  let final_lng = self.fixed_bearing_lng(x, y, pan, new_lng)
  self.set_center({ lng: wrap(final_lng, -180.0, 180.0), lat: final_lat, })
  self.set_zoom(old_zoom + zoom_adjustment(old_lat, self.center.lat))
}

///|
/// Near a pole a drag turns the globe about it like a dial (`fixedBearingLongitude`).
fn Globe::fixed_bearing_lng(
  self : Globe,
  x : Double,
  y : Double,
  pan : (Double, Double),
  new_lng : Double,
) -> Double {
  let old_lng = self.center.lng
  let old_lat = self.center.lat
  let pole_lat = if old_lat >= 0.0 { 90.0 } else { -90.0 }
  let (pole_x, pole_y) = self.project({ lng: 0.0, lat: pole_lat, })
  let rx = x - pole_x
  let ry = y - pole_y
  let r2 = rx * rx + ry * ry
  let ramp = clamp(
    1.0 - (@core.MAX_VALID_LATITUDE - old_lat.abs()) / 12.0,
    0.0,
    1.0,
  )
  let dial = ramp * ramp * (3.0 - 2.0 * ramp)
  let swing = modulo(new_lng - old_lng + 180.0, 360.0) - 180.0
  let mut dial_lng = 0.0
  if dial > 0.0 {
    let d_theta = (rx * pan.1 - ry * pan.0) /
      @cmp.maximum(r2, DIAL_MIN_RADIUS_PIXELS * DIAL_MIN_RADIUS_PIXELS)
    dial_lng = (if pole_lat > 0.0 { 1.0 } else { -1.0 }) *
      d_theta *
      180.0 /
      @math.PI
  }
  old_lng + (1.0 - dial) * swing + dial * dial_lng
}

///|
/// Where inertia after a pan of `pan` pixels eases the center to, and the
/// screen offset it eases with (`handlePanInertia`).
pub fn Globe::pan_inertia(
  self : Globe,
  pan : (Double, Double),
) -> (@core.LngLat, (Double, Double)) {
  if !self.is_globe() {
    let len = (pan.0 * pan.0 + pan.1 * pan.1).sqrt()
    let horizon = self.mercator().horizon().abs()
    let k = @cmp.minimum(horizon * 0.75 / len, 1.0)
    return (self.center, (pan.0 * k, pan.1 * k))
  }
  let b = self.bearing
  let (c, s) = (@math.cos(b), @math.sin(b))
  let rx = c * pan.0 - s * pan.1
  let ry = s * pan.0 + c * pan.1
  let normalized = self.zoom + zoom_adjustment(self.center.lat, 0.0)
  let lng_speed = lerp(
    1.0 / planet_scale(self.center.lat),
    1.0 / planet_scale(@cmp.minimum(self.center.lat.abs(), 60.0)),
    remap_saturate(normalized, 7.0, 3.0, 0.0, 1.0),
  )
  let per_pixel = 360.0 / circumference(self.world_size(), self.center.lat)
  let mut center : @core.LngLat = {
    lng: self.center.lng - rx * per_pixel * lng_speed,
    lat: clamp(self.center.lat + ry * per_pixel, -90.0, 90.0),
  }
  if (center.lng - self.center.lng).abs() > 180.0 {
    center = {
      lng: self.center.lng + 179.5 * sign(center.lng - self.center.lng),
      lat: center.lat,
    }
  }
  (center, (0.0, 0.0))
}
