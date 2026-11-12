// easeTo and flyTo as MapLibre GL JS 6.16.0 computes them (src/ui/camera.ts), BSD-3-Clause,
// Copyright (c) 2020 MapLibre contributors; the easing curve follows @mapbox/unitbezier
// (BSD-2-Clause, Copyright (C) 2008 Apple Inc.). See NOTICE.

///|
/// A cubic Bézier easing from (0, 0) to (1, 1) through control points
/// (`p1x`, `p1y`) and (`p2x`, `p2y`), solved for x as @mapbox/unitbezier does.
pub struct Bezier {
  priv ax : Double
  priv bx : Double
  priv cx : Double
  priv ay : Double
  priv by : Double
  priv cy : Double
}

///|
pub fn Bezier::new(
  p1x : Double,
  p1y : Double,
  p2x : Double,
  p2y : Double,
) -> Bezier {
  let cx = 3.0 * p1x
  let bx = 3.0 * (p2x - p1x) - cx
  let cy = 3.0 * p1y
  let by = 3.0 * (p2y - p1y) - cy
  { ax: 1.0 - cx - bx, bx, cx, ay: 1.0 - cy - by, by, cy, }
}

///|
/// MapLibre's default easing, control points (0.25, 0.1) and (0.25, 1).
pub fn Bezier::ease() -> Bezier {
  Bezier::new(0.25, 0.1, 0.25, 1.0)
}

///|
pub fn Bezier::at(self : Bezier, x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  if x >= 1.0 {
    return 1.0
  }
  let y = (t : Double) => ((self.ay * t + self.by) * t + self.cy) * t
  let mut t = x
  for _ in 0..<8 {
    let x2 = ((self.ax * t + self.bx) * t + self.cx) * t - x
    if x2.abs() < 1.0e-6 {
      return y(t)
    }
    let d2 = (3.0 * self.ax * t + 2.0 * self.bx) * t + self.cx
    if d2.abs() < 1.0e-6 {
      break
    }
    t -= x2 / d2
  }
  let mut t0 = 0.0
  let mut t1 = 1.0
  t = x
  for _ in 0..<20 {
    let x2 = ((self.ax * t + self.bx) * t + self.cx) * t
    if (x2 - x).abs() < 1.0e-6 {
      break
    }
    if x > x2 {
      t0 = t
    } else {
      t1 = t
    }
    t = (t0 + t1) * 0.5
  }
  y(t)
}

///|
/// `bearing` wrapped and moved by a turn toward `current`, so that easing
/// between them takes the short way (MapLibre's `_normalizeBearing`).
fn normalize_bearing(bearing : Double, current : Double) -> Double {
  let mut b = wrap180(bearing)
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
/// `p` a turn east or west so that the move from `from` goes the shorter way
/// round the world (MapLibre's `normalizeCenter`; not with bounds).
fn normalize_center(p : LngLat, from : LngLat) -> LngLat {
  let d = p.lng - from.lng
  {
    ..p,
    lng: p.lng +
    (if d > 180.0 { -360.0 } else if d < -180.0 { 360.0 } else { 0.0 }),
  }
}

///|
/// Where a camera move ends: what is left out stays as it is. `around` keeps
/// that point at its screen position through the move; `offset` (pixels)
/// places the new center that far from the screen center.
#derive(Debug, Eq)
pub(all) struct CameraTarget {
  center : LngLat?
  zoom : Double?
  bearing : Double?
  pitch : Double?
  around : LngLat?
  offset : (Double, Double)
}

///|
pub fn CameraTarget::new(
  center? : LngLat,
  zoom? : Double,
  bearing? : Double,
  pitch? : Double,
  around? : LngLat,
  offset~ : (Double, Double) = (0.0, 0.0),
) -> CameraTarget {
  { center, zoom, bearing, pitch, around, offset, }
}

///|
/// What `ease_to` and `fly_to` start from: the screen point the center goes to,
/// the end camera, the start and the way to the end in world pixels, and the
/// end bearing and pitch.
priv struct Move {
  point : (Double, Double)
  to : Camera
  from : (Double, Double)
  delta : (Double, Double)
  end_bearing : Double
  end_pitch : Double
}

///|
fn Transform::move_to(self : Transform, target : CameraTarget) -> Move {
  let c = self.camera
  let point = (
    self.width / 2.0 + target.offset.0,
    self.height / 2.0 + target.offset.1,
  )
  let at_offset = self.unproject(point.0, point.1)
  let to = constrain_once(
    {
      ..c,
      center: target.center.unwrap_or(at_offset),
      zoom: target.zoom.unwrap_or(c.zoom),
    },
    self.limits,
    self.width,
    self.height,
  )
  let ws = self.world_size()
  let f = at_offset.to_mercator()
  let t = (if self.limits.bounds is None {
    normalize_center(to.center, c.center)
  } else {
    to.center
  }).to_mercator()
  let tx = t.x
  {
    point,
    to,
    from: (f.x * ws, f.y * ws),
    delta: ((tx - f.x) * ws, (t.y - f.y) * ws),
    end_bearing: match target.bearing {
      Some(b) => normalize_bearing(b, c.bearing)
      None => c.bearing
    },
    end_pitch: target.pitch.unwrap_or(c.pitch),
  }
}

///|
/// An `ease_to` move: the camera at any fraction of it (`at`).
pub struct Ease {
  priv start : Transform
  priv start_zoom : Double
  priv end_zoom : Double
  priv start_bearing : Double
  priv end_bearing : Double
  priv start_pitch : Double
  priv end_pitch : Double
  priv around : (LngLat, Double, Double)?
  priv from : (Double, Double)
  priv delta : (Double, Double)
  priv point : (Double, Double)
}

///|
/// A move from this camera to `target` that eases zoom, bearing and pitch
/// together and slides the center along a path that speeds up when zooming
/// (MapLibre's `easeTo`).
pub fn Transform::ease_to(self : Transform, target : CameraTarget) -> Ease {
  let c = self.camera
  let m = self.move_to(target)
  {
    start: self,
    start_zoom: c.zoom,
    end_zoom: m.to.zoom,
    start_bearing: c.bearing,
    end_bearing: m.end_bearing,
    start_pitch: c.pitch,
    end_pitch: m.end_pitch,
    around: target.around.map(a => {
      let (x, y) = self.project(a)
      (a, x, y)
    }),
    from: m.from,
    delta: m.delta,
    point: m.point,
  }
}

///|
fn lerp(a : Double, b : Double, k : Double) -> Double {
  a * (1.0 - k) + b * k
}

///|
/// The camera at eased fraction `k` (0 to 1) of the move.
pub fn Ease::at(self : Ease, k : Double) -> Camera {
  let c = self.start.camera
  let zoom = if self.end_zoom != self.start_zoom {
    lerp(self.start_zoom, self.end_zoom, k)
  } else {
    c.zoom
  }
  let tr = self.start.with_camera({
    ..c,
    zoom,
    bearing: lerp(self.start_bearing, self.end_bearing, k),
    pitch: lerp(self.start_pitch, self.end_pitch, k),
  })
  match self.around {
    Some((a, x, y)) => tr.at_point(a, x, y)
    None => {
      let final_scale = @math.pow(2.0, self.end_zoom - self.start_zoom)
      let scale = @math.pow(2.0, tr.camera.zoom - self.start_zoom)
      let base = if self.end_zoom > self.start_zoom {
        @cmp.minimum(2.0, final_scale)
      } else {
        @cmp.maximum(0.5, final_scale)
      }
      let speedup = @math.pow(base, 1.0 - k)
      let ws = tr.world_size()
      let x = (self.from.0 + self.delta.0 * k * speedup) * scale
      let y = (self.from.1 + self.delta.1 * k * speedup) * scale
      let p = ({ x: x / ws, y: y / ws, } : MercatorCoord).to_lnglat()
      tr.at_point(
        { lng: wrap180(p.lng), lat: p.lat, },
        self.point.0,
        self.point.1,
      )
    }
  }
}

///|
/// A `fly_to` flight: its natural `duration` in milliseconds and the camera
/// at any fraction of it (`at`).
pub struct Flight {
  priv start : Transform
  priv start_zoom : Double
  priv target : Camera
  priv start_bearing : Double
  priv end_bearing : Double
  priv start_pitch : Double
  priv end_pitch : Double
  priv from : (Double, Double)
  priv delta : (Double, Double)
  priv start_world : Double
  priv point : (Double, Double)
  priv rho : Double
  priv r0 : Double
  priv length : Double
  priv path : Bool
  priv dir : Double
  duration : Double
}

///|
/// Hyperbolic sine from `exp`, as the camera ports compute it (van Wijk and Nuij's flight).
pub fn sinh(x : Double) -> Double {
  (@math.exp(x) - @math.exp(-x)) / 2.0
}

///|
/// Hyperbolic cosine from `exp`, as `sinh`.
pub fn cosh(x : Double) -> Double {
  (@math.exp(x) + @math.exp(-x)) / 2.0
}

///|
fn tanh(x : Double) -> Double {
  sinh(x) / cosh(x)
}

///|
/// A flight to `target` zooming out and back in on van Wijk and Nuij's path
/// (MapLibre's `flyTo`): `curve` is ρ, `speed` screenfuls a second, `min_zoom`
/// the lowest passed. None when too short to fly: ease instead.
pub fn Transform::fly_to(
  self : Transform,
  target : CameraTarget,
  curve~ : Double = 1.42,
  speed~ : Double = 1.2,
  screen_speed? : Double,
  min_zoom? : Double,
) -> Flight? {
  let c = self.camera
  let m = self.move_to(target)
  let to = m.to
  let delta = m.delta
  let u1 = (delta.0 * delta.0 + delta.1 * delta.1).sqrt()
  let scale_of_zoom = @math.pow(2.0, to.zoom - c.zoom)
  let requested = min_zoom.unwrap_or(self.limits.min_zoom)
  let lowest = @cmp.minimum(
    @cmp.maximum(requested, self.limits.min_zoom),
    @cmp.minimum(c.zoom, to.zoom),
  )
  let lowest = constrain_once(
      { ..to, zoom: lowest, },
      self.limits,
      self.width,
      self.height,
    ).zoom
  let scale_of_min = @math.pow(2.0, lowest - c.zoom)
  let w0 = @cmp.maximum(self.width, self.height)
  let w1 = w0 / scale_of_zoom
  let w_max = w0 / scale_of_min
  let rho = @cmp.minimum(curve, (w_max / u1 * 2.0).sqrt())
  let rho2 = rho * rho
  let zoom_out = (descent : Bool) => {
    let sign = if descent { -1.0 } else { 1.0 }
    let b = (w1 * w1 - w0 * w0 + sign * rho2 * rho2 * u1 * u1) /
      (2.0 * (if descent { w1 } else { w0 }) * rho2 * u1)
    @math.ln((b * b + 1.0).sqrt() - b)
  }
  let r0 = zoom_out(false)
  let mut length = (zoom_out(true) - r0) / rho
  let mut path = true
  let mut dir = 1.0
  if u1.abs() < 0.000002 || length.is_nan() || length.is_inf() {
    if (w0 - w1).abs() < 0.000001 {
      return None
    }
    dir = if w1 < w0 { -1.0 } else { 1.0 }
    length = @math.ln(w1 / w0).abs() / rho
    path = false
  }
  let v = match screen_speed {
    Some(s) => s / rho
    None => speed
  }
  Some({
    start: self,
    start_zoom: c.zoom,
    target: to,
    start_bearing: c.bearing,
    end_bearing: m.end_bearing,
    start_pitch: c.pitch,
    end_pitch: m.end_pitch,
    from: m.from,
    delta,
    start_world: self.world_size(),
    point: m.point,
    rho,
    r0,
    length,
    path,
    dir,
    duration: 1000.0 * length / v,
  })
}

///|
/// The camera at eased fraction `k` (0 to 1) of the flight.
pub fn Flight::at(self : Flight, k : Double) -> Camera {
  let s = k * self.length
  let (w, u) = if self.path {
    let w0 = @cmp.maximum(self.start.width, self.start.height)
    (
      cosh(self.r0) / cosh(self.r0 + self.rho * s),
      w0 *
      (
        (cosh(self.r0) * tanh(self.r0 + self.rho * s) - sinh(self.r0)) /
        (self.rho * self.rho)
      ) /
      (self.delta.0 * self.delta.0 + self.delta.1 * self.delta.1).sqrt(),
    )
  } else {
    (@math.exp(self.dir * self.rho * s), 0.0)
  }
  let c = self.start.camera
  let zoom = if k == 1.0 {
    self.target.zoom
  } else {
    self.start_zoom + @math.log2(1.0 / w)
  }
  let tr = self.start.with_camera({
    ..c,
    zoom,
    bearing: lerp(self.start_bearing, self.end_bearing, k),
    pitch: lerp(self.start_pitch, self.end_pitch, k),
  })
  let center = if k == 1.0 {
    self.target.center
  } else {
    let x = self.from.0 + self.delta.0 * u
    let y = self.from.1 + self.delta.1 * u
    let p = (
      { x: x / self.start_world, y: y / self.start_world, } : MercatorCoord).to_lnglat()
    { lng: wrap180(p.lng), lat: p.lat, }
  }
  tr.at_point(center, self.point.0, self.point.1)
}
