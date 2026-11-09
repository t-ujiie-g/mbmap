// Terrain picks as MapLibre GL JS 6.16.0 makes them on the CPU (mercator_
// transform.ts, terrain_coverage.ts), BSD-3-Clause, Copyright (c) 2020
// MapLibre contributors; see NOTICE.

///|
/// World pixels between samples along a ray, and the most samples taken.
const RAY_STEP : Double = 4.0

///|
const RAY_MAX_SAMPLES : Int32 = 512

///|
/// The last fraction of the way to a location in which terrain does not hide
/// it, so the ground it stands on never does.
const OCCLUSION_MARGIN : Double = 0.01

///|
/// The terrain drawn under a view: `height` gives the ground (meters,
/// exaggerated) at a mercator point, None where no terrain is drawn; every
/// height lies within `lowest` and `highest`.
pub(all) struct Terrain {
  height : (Double, Double) -> Double?
  lowest : Double
  highest : Double
}

///|
/// A ray from the near plane (`near`, world pixels relative to the center,
/// z above sea level) to the far plane, `delta` long.
priv struct Ray {
  near : (Double, Double, Double)
  delta : (Double, Double, Double)
}

///|
fn Transform::ray(self : Transform, x : Double, y : Double) -> Ray {
  let (ax, ay, az, bx, by, bz) = self.screen_ray(x, y)
  { near: (ax, ay, az), delta: (bx - ax, by - ay, bz - az), }
}

///|
fn Ray::at(self : Ray, t : Double) -> (Double, Double, Double) {
  (
    self.near.0 + t * self.delta.0,
    self.near.1 + t * self.delta.1,
    self.near.2 + t * self.delta.2,
  )
}

///|
/// The ray parameter of the point on it closest to `p`.
fn Ray::parameter(self : Ray, p : (Double, Double, Double)) -> Double {
  let (dx, dy, dz) = self.delta
  (
    (p.0 - self.near.0) * dx +
    (p.1 - self.near.1) * dy +
    (p.2 - self.near.2) * dz
  ) /
  (dx * dx + dy * dy + dz * dz)
}

///|
/// The ground (world pixels) under the ray's point at `t`, None off the
/// terrain.
fn Transform::ground_under(
  self : Transform,
  terrain : Terrain,
  ray : Ray,
  t : Double,
) -> Double? {
  let c = self.camera.center.to_mercator()
  let ws = self.world_size()
  let (x, y, _) = ray.at(t)
  let my = c.y + y / ws
  if my < 0.0 || my >= 1.0 {
    return None
  }
  let mx = c.x + x / ws
  (terrain.height)(mx - mx.floor(), my).map(h => h * self.pixels_per_meter())
}

///|
fn Transform::below_terrain(
  self : Transform,
  terrain : Terrain,
  ray : Ray,
  t : Double,
) -> Bool {
  match self.ground_under(terrain, ray, t) {
    Some(g) => ray.at(t).2 <= g + 1.0e-6 * self.pixels_per_meter()
    None => false
  }
}

///|
/// The ray parameter where the ray first enters the terrain from above, if
/// it does (MapLibre's `_raycastTerrain`: samples `RAY_STEP` apart within the
/// terrain's height range, then bisection).
fn Transform::raycast(
  self : Transform,
  terrain : Terrain,
  ray : Ray,
) -> Double? {
  let ppm = self.pixels_per_meter()
  // MapLibre pads the range by 10 m so flat terrain still brackets.
  let high = (terrain.highest + 10.0) * ppm
  let low = (terrain.lowest - 10.0) * ppm
  let (dx, dy, dz) = ray.delta
  let z0 = ray.near.2
  let mut t0 = 0.0
  let mut t1 = 1.0
  if dz == 0.0 {
    if z0 > high || z0 < low {
      return None
    }
  } else {
    let th = (high - z0) / dz
    let tl = (low - z0) / dz
    t0 = @cmp.maximum(t0, @cmp.minimum(th, tl))
    t1 = @cmp.minimum(t1, @cmp.maximum(th, tl))
    if t0 > t1 {
      return None
    }
  }
  let length = (dx * dx + dy * dy).sqrt()
  let samples = @cmp.maximum(
    1,
    @cmp.minimum(
      RAY_MAX_SAMPLES,
      (length * (t1 - t0) / RAY_STEP).ceil().to_int(),
    ),
  )
  let below = t => self.below_terrain(terrain, ray, t)
  let mut previous = 0.0
  let mut above = !below(0.0)
  for i in 0..<=samples {
    let t = t0 + (t1 - t0) * i.to_double() / samples.to_double()
    if !above {
      above = !below(t)
    } else if below(t) {
      let mut lo = previous
      let mut hi = t
      let tolerance = 1.0e-3 / length
      for j = 0; j < 40 && hi - lo > tolerance; j = j + 1 {
        let mid = (lo + hi) / 2.0
        if below(mid) {
          hi = mid
        } else {
          lo = mid
        }
      }
      let f = (t : Double, g : Double) => z0 + t * dz - g
      return match
        (
          self.ground_under(terrain, ray, lo),
          self.ground_under(terrain, ray, hi),
        ) {
        (Some(glo), Some(ghi)) if f(lo, glo) > f(hi, ghi) => {
          let (flo, fhi) = (f(lo, glo), f(hi, ghi))
          Some(
            @cmp.maximum(
              lo,
              @cmp.minimum(hi, lo + flo * (hi - lo) / (flo - fhi)),
            ),
          )
        }
        _ => Some(hi)
      }
    }
    previous = t
  }
  None
}

///|
/// Whether `terrain` hides `p` at `elevation` meters from the camera, or `p`
/// is behind it or beyond the far plane (MapLibre's `isLocationOccluded`).
pub fn Transform::occluded(
  self : Transform,
  p : LngLat,
  elevation : Double,
  terrain : Terrain,
) -> Bool {
  let c = self.camera.center.to_mercator()
  let m = p.to_mercator()
  let ws = self.world_size()
  let at = (
    (m.x - c.x) * ws,
    (m.y - c.y) * ws,
    elevation * self.pixels_per_meter(),
  )
  let (x, y, z, w) = self.view.apply(at.0, at.1, at.2, 1.0)
  if w <= 0.0 || z > w {
    return true
  }
  let ray = self.ray(
    (x / w + 1.0) / 2.0 * self.width,
    (1.0 - y / w) / 2.0 * self.height,
  )
  match self.raycast(terrain, ray) {
    None => false
    Some(t) => {
      let hit = ray.at(t)
      let g = self.ground_under(terrain, ray, t).unwrap_or(hit.2)
      ray.parameter((hit.0, hit.1, g)) <
      ray.parameter(at) * (1.0 - OCCLUSION_MARGIN)
    }
  }
}

///|
/// The point under screen point (x, y): where its ray first meets `terrain`,
/// or else the plane at the center's height (MapLibre's `pointLocation` with
/// terrain).
pub fn Transform::unproject_on(
  self : Transform,
  x : Double,
  y : Double,
  terrain : Terrain,
) -> LngLat {
  let ray = self.ray(x, y)
  let (dx, dy, dz) = ray.delta
  let t = match self.raycast(terrain, ray) {
    Some(t) => t
    None => {
      let z = self.elevation * self.pixels_per_meter()
      if dz == 0.0 {
        0.0
      } else {
        (z - ray.near.2) / dz
      }
    }
  }
  let c = self.camera.center.to_mercator()
  let ws = self.world_size()
  let m : MercatorCoord = {
    x: c.x + (ray.near.0 + t * dx) / ws,
    y: c.y + (ray.near.1 + t * dy) / ws,
  }
  m.to_lnglat()
}

///|
/// The ray under screen point (x, y): its start on the near plane (world pixels relative to the
/// center, z up), its direction (unit) and its length to the far plane.
pub fn Transform::eye_ray(
  self : Transform,
  x : Double,
  y : Double,
) -> ((Double, Double, Double), (Double, Double, Double), Double) {
  let (ax, ay, az, bx, by, bz) = self.screen_ray(x, y)
  let (dx, dy, dz) = (bx - ax, by - ay, bz - az)
  let length = (dx * dx + dy * dy + dz * dz).sqrt()
  ((ax, ay, az), (dx / length, dy / length, dz / length), length)
}

///|
/// How far along the ray from `from` (world pixels relative to the center, z
/// up) toward `dir` (unit) it first meets `terrain`, or without terrain the
/// sea-level plane, within `length`; None if it does not.
pub fn Transform::ground_hit(
  self : Transform,
  from : (Double, Double, Double),
  dir : (Double, Double, Double),
  length : Double,
  terrain : Terrain?,
) -> Double? {
  match terrain {
    Some(t) => {
      let ray = {
        near: from,
        delta: (dir.0 * length, dir.1 * length, dir.2 * length),
      }
      self.raycast(t, ray).map(f => f * length)
    }
    None => {
      if dir.2 >= 0.0 || from.2 < 0.0 {
        return None
      }
      let d = -from.2 / dir.2
      if d <= length {
        Some(d)
      } else {
        None
      }
    }
  }
}
