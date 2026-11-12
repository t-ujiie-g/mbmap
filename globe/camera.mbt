// MapLibre GL JS 6.16.0's globe and mercator camera helpers (src/geo/projection/) and the parts of
// src/ui/camera.ts that drive them, BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.

///|
/// Moves the camera at once (MapLibre's `jumpTo`); left out stays as it is.
pub fn Globe::jump_to(
  self : Globe,
  center? : @core.LngLat,
  zoom? : Double,
  bearing? : Double,
  pitch? : Double,
) -> Unit {
  if self.is_globe() {
    let start_lat = self.center.lat
    let c = center.unwrap_or(self.center)
    self.set_center(wrapped(self.constrain(c, self.zoom).0))
    let target = match zoom {
      Some(z) => z
      None => self.zoom + zoom_adjustment(start_lat, self.center.lat)
    }
    if self.zoom != target {
      self.set_zoom(target)
      self.set_center(wrapped(self.constrain(c, self.zoom).0))
    }
  } else {
    if zoom is Some(z) && z != self.zoom {
      self.set_zoom(z)
    }
    if center is Some(c) {
      self.set_center(c)
    }
  }
  if bearing is Some(b) && self.camera().bearing != b {
    self.set_bearing(b)
  }
  if pitch is Some(p) && self.camera().pitch != p {
    self.set_pitch(p)
  }
}

///|
/// `bearing` turned by whole turns to lie nearest `current` (`_normalizeBearing`).
fn normalize_bearing(bearing : Double, current : Double) -> Double {
  let mut b = wrap(bearing, -180.0, 180.0)
  let diff = (b - current).abs()
  if (b - 360.0 - current).abs() < diff {
    b -= 360.0
  }
  if (b + 360.0 - current).abs() < diff {
    b += 360.0
  }
  b
}

///|
/// `center` a whole turn nearer the camera's (`normalizeCenter`), unless the
/// longitudes are bounded.
fn Globe::normalize_center(self : Globe, c : @core.LngLat) -> @core.LngLat {
  if self.limits.bounds is Some(_) {
    return c
  }
  let d = c.lng - self.center.lng
  {
    lng: c.lng +
    (if d > 180.0 { -360.0 } else if d < -180.0 { 360.0 } else { 0.0 }),
    lat: c.lat,
  }
}

///|
/// Mercator world pixels of `p` at `world_size`, latitude kept to the limit
/// (`projectToWorldCoordinates`).
fn world_point(world_size : Double, p : @core.LngLat) -> (Double, Double) {
  let max = @core.MAX_VALID_LATITUDE
  let m = ({ lng: p.lng, lat: clamp(p.lat, -max, max), } : @core.LngLat).to_mercator()
  (m.x * world_size, m.y * world_size)
}

///|
fn world_lnglat(world_size : Double, x : Double, y : Double) -> @core.LngLat {
  ({ x: x / world_size, y: y / world_size, } : @core.MercatorCoord).to_lnglat()
}

///|
/// The screen point the center goes to, moved by `offset`, kept on screen.
fn Globe::offset_point(
  self : Globe,
  offset : (Double, Double),
) -> (Double, Double) {
  (
    clamp(self.width / 2.0 + offset.0, 0.0, self.width),
    clamp(self.height / 2.0 + offset.1, 0.0, self.height),
  )
}

///|
/// Sets pitch then bearing a fraction `k` of the way (`updateRotation`).
fn Globe::rotate_by(
  self : Globe,
  from : (Double, Double),
  to : (Double, Double),
  k : Double,
) -> Unit {
  if from != to {
    self.set_pitch(lerp(from.0, to.0, k))
    self.set_bearing(lerp(from.1, to.1, k))
  }
}

///|
/// An `ease_to` move. `at` must be called with growing fractions, as frames
/// come: it changes the camera it holds and returns it.
pub struct GlobeEase {
  priv tr : Globe
  priv step : (Double) -> Unit
}

///|
/// The camera at eased fraction `k` (0 to 1); the transition then follows the
/// new zoom, as MapLibre's next frame takes it.
pub fn GlobeEase::at(self : GlobeEase, k : Double) -> @core.Camera {
  (self.step)(k)
  self.tr.update_transition()
  self.tr.camera()
}

///|
/// The camera the move changes.
pub fn GlobeEase::transform(self : GlobeEase) -> Globe {
  self.tr
}

///|
/// A move to `target` easing zoom, bearing and pitch together (MapLibre's
/// `easeTo`), on a copy of this camera; on the globe the center moves along
/// an even path over the sphere.
pub fn Globe::ease_to(self : Globe, target : @core.CameraTarget) -> GlobeEase {
  let tr = self.copy()
  let start = tr.camera()
  let end_bearing = match target.bearing {
    Some(b) => normalize_bearing(b, start.bearing)
    None => start.bearing
  }
  let end_pitch = target.pitch.unwrap_or(start.pitch)
  let around = target.around.map(a => (a, tr.project(a)))
  let from_angles = (start.pitch, start.bearing)
  let to_angles = (end_pitch, end_bearing)
  let step = if tr.is_globe() {
    tr.globe_ease(target, around, from_angles, to_angles)
  } else {
    tr.mercator_ease(target, around, from_angles, to_angles)
  }
  { tr, step, }
}

///|
fn Globe::globe_ease(
  tr : Globe,
  target : @core.CameraTarget,
  around : (@core.LngLat, (Double, Double))?,
  from_angles : (Double, Double),
  to_angles : (Double, Double),
) -> (Double) -> Unit {
  let start_zoom = tr.zoom
  let start_center = tr.center
  let pre = target.center.unwrap_or(start_center)
  let constrained = tr.normalize_center(
    tr.constrain(pre, target.zoom.unwrap_or(start_zoom)).0,
  )
  let cloned = tr.copy()
  cloned.set_center(constrained)
  cloned.set_zoom(
    target.zoom.unwrap_or(
      start_zoom + zoom_adjustment(start_center.lat, pre.lat),
    ),
  )
  cloned.set_bearing(to_angles.1)
  let (px, py) = tr.offset_point(target.offset)
  cloned.set_location_at_point(constrained, px, py)
  let (ox, oy) = target.offset
  let end_center = if (ox * ox + oy * oy).sqrt() > 0.0 {
    cloned.center
  } else {
    constrained
  }
  let end_zoom = target.zoom.unwrap_or(
    start_zoom + zoom_adjustment(start_center.lat, end_center.lat),
  )
  let start_norm = start_zoom + zoom_adjustment(start_center.lat, 0.0)
  let end_norm = end_zoom + zoom_adjustment(end_center.lat, 0.0)
  let d_lng = angle_difference(start_center.lng, end_center.lng)
  let d_lat = angle_difference(start_center.lat, end_center.lat)
  let final_scale = zoom_scale(end_norm - start_norm)
  let zooming = end_zoom != start_zoom
  fn(k) {
    tr.rotate_by(from_angles, to_angles, k)
    match around {
      Some((a, (x, y))) => tr.set_location_at_point(a, x, y)
      None => {
        let base = if end_norm > start_norm {
          @cmp.minimum(2.0, final_scale)
        } else {
          @cmp.maximum(0.5, final_scale)
        }
        let factor = k * @math.pow(base, 1.0 - k)
        tr.set_center(
          wrapped(interpolate_center(start_center, d_lng, d_lat, factor)),
        )
      }
    }
    if zooming {
      tr.set_zoom(
        lerp(start_norm, end_norm, k) + zoom_adjustment(0.0, tr.center.lat),
      )
    }
    if k == 1.0 && around is None {
      tr.set_center(wrapped(end_center))
    }
  }
}

///|
fn Globe::mercator_ease(
  tr : Globe,
  target : @core.CameraTarget,
  around : (@core.LngLat, (Double, Double))?,
  from_angles : (Double, Double),
  to_angles : (Double, Double),
) -> (Double) -> Unit {
  let start_zoom = tr.zoom
  let point = (
    tr.width / 2.0 + target.offset.0,
    tr.height / 2.0 + target.offset.1,
  )
  let at_offset = tr.unproject(point.0, point.1)
  let (c, end_zoom) = tr.constrain(
    target.center.unwrap_or(at_offset),
    target.zoom.unwrap_or(start_zoom),
  )
  let center = tr.normalize_center(c)
  let ws = tr.world_size()
  let from = world_point(ws, at_offset)
  let to = world_point(ws, center)
  let delta = (to.0 - from.0, to.1 - from.1)
  let final_scale = zoom_scale(end_zoom - start_zoom)
  let zooming = end_zoom != start_zoom
  fn(k) {
    if zooming {
      tr.set_zoom(lerp(start_zoom, end_zoom, k))
    }
    tr.rotate_by(from_angles, to_angles, k)
    match around {
      Some((a, (x, y))) => tr.set_location_at_point(a, x, y)
      None => {
        let scale = zoom_scale(tr.zoom - start_zoom)
        let base = if end_zoom > start_zoom {
          @cmp.minimum(2.0, final_scale)
        } else {
          @cmp.maximum(0.5, final_scale)
        }
        let f = k * @math.pow(base, 1.0 - k)
        let x = (from.0 + delta.0 * f) * scale
        let y = (from.1 + delta.1 * f) * scale
        let c = wrapped(world_lnglat(tr.world_size(), x, y))
        tr.set_location_at_point(c, point.0, point.1)
      }
    }
  }
}

///|
/// A `fly_to` flight: its natural `duration` in milliseconds and the camera
/// at growing fractions of it (`at`, as `GlobeEase::at`).
pub struct GlobeFlight {
  priv tr : Globe
  priv frame : (Double) -> Unit
  duration : Double
}

///|
pub fn GlobeFlight::at(self : GlobeFlight, k : Double) -> @core.Camera {
  (self.frame)(k)
  self.tr.update_transition()
  self.tr.camera()
}

///|
/// The camera the flight changes.
pub fn GlobeFlight::transform(self : GlobeFlight) -> Globe {
  self.tr
}

///|
/// What a flight's start leaves for its frames: where the center goes, its
/// zoom scale and the lowest zoom's, the path length in pixels and the frame
/// for a fraction, scale and share of the path.
priv struct FlyPlan {
  scale_of_zoom : Double
  scale_of_min_zoom : Double
  path_length : Double
  step : (Double, Double, Double) -> Unit
}

///|
/// A flight to `target` zooming out and back in on van Wijk and Nuij's path
/// (MapLibre's `flyTo`), on a copy of this camera. None when too short to fly:
/// ease instead.
pub fn Globe::fly_to(
  self : Globe,
  target : @core.CameraTarget,
  curve~ : Double = 1.42,
  speed~ : Double = 1.2,
  screen_speed? : Double,
  min_zoom? : Double,
) -> GlobeFlight? {
  let tr = self.copy()
  let start = tr.camera()
  let end_bearing = match target.bearing {
    Some(b) => normalize_bearing(b, start.bearing)
    None => start.bearing
  }
  let end_pitch = target.pitch.unwrap_or(start.pitch)
  let point = (
    tr.width / 2.0 + target.offset.0,
    tr.height / 2.0 + target.offset.1,
  )
  let at_offset = tr.unproject(point.0, point.1)
  let plan = if tr.is_globe() {
    tr.globe_fly(target, at_offset, end_bearing, min_zoom)
  } else {
    tr.mercator_fly(target, at_offset, min_zoom)
  }
  let w0 = @cmp.maximum(tr.width, tr.height)
  let w1 = w0 / plan.scale_of_zoom
  let u1 = plan.path_length
  let w_max = w0 / plan.scale_of_min_zoom
  let rho = @cmp.minimum(curve, (w_max / u1 * 2.0).sqrt())
  let rho2 = rho * rho
  let zoom_out = (descent : Bool) => {
    let b = (
        w1 * w1 -
        w0 * w0 +
        (if descent { -1.0 } else { 1.0 }) * rho2 * rho2 * u1 * u1
      ) /
      (2.0 * (if descent { w1 } else { w0 }) * rho2 * u1)
    @math.ln((b * b + 1.0).sqrt() - b)
  }
  let r0 = zoom_out(false)
  let mut length = (zoom_out(true) - r0) / rho
  let mut w : (Double) -> Double = s => {
    @core.cosh(r0) / @core.cosh(r0 + rho * s)
  }
  let mut u : (Double) -> Double = s => {
    w0 *
    (
      (
        @core.cosh(r0) * (@core.sinh(r0 + rho * s) / @core.cosh(r0 + rho * s)) -
        @core.sinh(r0)
      ) /
      rho2
    ) /
    u1
  }
  if u1.abs() < 0.000002 || length.is_nan() || length.is_inf() {
    if (w0 - w1).abs() < 0.000001 {
      return None
    }
    let dir = if w1 < w0 { -1.0 } else { 1.0 }
    length = @math.ln(w1 / w0).abs() / rho
    u = _ => 0.0
    w = s => @math.exp(dir * rho * s)
  }
  let v = match screen_speed {
    Some(s) => s / rho
    None => speed
  }
  let rotating = start.bearing != end_bearing
  let pitching = start.pitch != end_pitch
  let total = length
  let frame = fn(k : Double) {
    let s = k * total
    if rotating {
      tr.set_bearing(lerp(start.bearing, end_bearing, k))
    }
    if pitching {
      tr.set_pitch(lerp(start.pitch, end_pitch, k))
    }
    (plan.step)(k, 1.0 / w(s), u(s))
  }
  Some({ tr, frame, duration: 1000.0 * length / v, })
}

///|
fn Globe::lowest_zoom(
  tr : Globe,
  requested : Double?,
  start : Double,
  end : Double,
) -> Double {
  let effective = @cmp.maximum(
    requested.unwrap_or(tr.limits.min_zoom),
    tr.limits.min_zoom,
  )
  @cmp.minimum(effective, @cmp.minimum(start, end))
}

///|
fn Globe::mercator_fly(
  tr : Globe,
  target : @core.CameraTarget,
  at_offset : @core.LngLat,
  min_zoom : Double?,
) -> FlyPlan {
  let start_zoom = tr.zoom
  let (c, target_zoom) = tr.constrain(
    target.center.unwrap_or(at_offset),
    target.zoom.unwrap_or(start_zoom),
  )
  let center = tr.normalize_center(c)
  let ws = tr.world_size()
  let from = world_point(ws, at_offset)
  let to = world_point(ws, center)
  let delta = (to.0 - from.0, to.1 - from.1)
  let lowest = tr.lowest_zoom(min_zoom, start_zoom, target_zoom)
  let point = (
    tr.width / 2.0 + target.offset.0,
    tr.height / 2.0 + target.offset.1,
  )
  {
    scale_of_zoom: zoom_scale(target_zoom - start_zoom),
    scale_of_min_zoom: zoom_scale(tr.constrain(center, lowest).1 - start_zoom),
    path_length: (delta.0 * delta.0 + delta.1 * delta.1).sqrt(),
    step: fn(k, scale, share) {
      tr.set_zoom(
        if k == 1.0 {
          target_zoom
        } else {
          start_zoom + scale_zoom(scale)
        },
      )
      let c = if k == 1.0 {
        center
      } else {
        world_lnglat(ws, from.0 + delta.0 * share, from.1 + delta.1 * share)
      }
      tr.set_location_at_point(wrapped(c), point.0, point.1)
    },
  }
}

///|
fn Globe::globe_fly(
  tr : Globe,
  target : @core.CameraTarget,
  at_offset : @core.LngLat,
  end_bearing : Double,
  min_zoom : Double?,
) -> FlyPlan {
  let start_center = tr.center
  let start_zoom = tr.zoom
  let constrained = tr.constrain(
      target.center.unwrap_or(at_offset),
      target.zoom.unwrap_or(start_zoom),
    ).0
  let target_zoom = target.zoom.unwrap_or(
    tr.zoom + zoom_adjustment(tr.center.lat, constrained.lat),
  )
  let cloned = tr.copy()
  cloned.set_center(constrained)
  cloned.set_zoom(target_zoom)
  cloned.set_bearing(end_bearing)
  let (px, py) = tr.offset_point(target.offset)
  cloned.set_location_at_point(constrained, px, py)
  let target_center = tr.normalize_center(cloned.center)
  let path_length = pixel_distance(
    tr.world_size(),
    tr.center.lat,
    start_center,
    target_center,
  )
  let start_norm = start_zoom + zoom_adjustment(start_center.lat, 0.0)
  let target_norm = target_zoom + zoom_adjustment(target_center.lat, 0.0)
  let effective = @cmp.maximum(
    min_zoom.unwrap_or(tr.limits.min_zoom),
    tr.limits.min_zoom,
  )
  let lowest_norm = @cmp.minimum(
    effective + zoom_adjustment(target_center.lat, 0.0),
    @cmp.minimum(start_norm, target_norm),
  )
  let lowest = tr.constrain(
      target_center,
      lowest_norm + zoom_adjustment(0.0, target_center.lat),
    ).1
  let d_lng = angle_difference(start_center.lng, target_center.lng)
  let d_lat = angle_difference(start_center.lat, target_center.lat)
  {
    scale_of_zoom: zoom_scale(target_norm - start_norm),
    scale_of_min_zoom: zoom_scale(
      lowest + zoom_adjustment(target_center.lat, 0.0) - start_norm,
    ),
    path_length,
    step: fn(k, scale, share) {
      let c = if k == 1.0 {
        target_center
      } else {
        interpolate_center(start_center, d_lng, d_lat, share)
      }
      tr.set_center(wrapped(c))
      tr.set_zoom(
        if k == 1.0 {
          target_zoom
        } else {
          start_norm + scale_zoom(scale) + zoom_adjustment(0.0, c.lat)
        },
      )
      if k == 1.0 {
        tr.set_center(wrapped(target_center))
      }
    },
  }
}
