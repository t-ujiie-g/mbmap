// @turf/clusters-dbscan 7.4.0 with the parts of @turf/distance and
// @turf/helpers it uses (MIT License, Copyright (c) 2017 TurfJS). See NOTICE.

///|
/// `dbscan`'s second value per row: Turf's `properties.dbscan` "core".
pub const DBSCAN_CORE : Int32 = 0

///|
/// "edge".
pub const DBSCAN_EDGE : Int32 = 1

///|
/// "noise".
pub const DBSCAN_NOISE : Int32 = 2

///|
/// A row Turf does not cluster: not a Point, or a Point without coordinates.
pub const DBSCAN_SKIPPED : Int32 = 3

///|
const PI : Double = 3.141592653589793

///|
/// Turf's factor for kilometers (`earthRadius / 1e3`).
let km_factor : Double = 6371008.8 / 1000.0

///|
/// Turf's `degreesToRadians`, which first takes the degrees modulo 360.
fn radians(degrees : Double) -> Double {
  degrees % 360.0 * PI / 180.0
}

///|
/// JavaScript's `Math.max` and `Math.min`: NaN if either is.
fn js_max(a : Double, b : Double) -> Double {
  if is_nan(a) || is_nan(b) {
    @double.not_a_number
  } else if a > b {
    a
  } else {
    b
  }
}

///|
fn js_min(a : Double, b : Double) -> Double {
  if is_nan(a) || is_nan(b) {
    @double.not_a_number
  } else if a < b {
    a
  } else {
    b
  }
}

///|
/// The points with their x order, for Turf's `regionQuery`. Turf's rbush is
/// built with as many entries per node as points, so it is one leaf scanned
/// whole; scanning the x range in order finds the same neighbors.
priv struct Region {
  pts : Points
  trig : @core.Trig
  max_distance : Double
  lat_degrees : Double
  order : FixedArray[Int32]
  sorted_x : FixedArray[Double]
  cos_lat : FixedArray[Double]
  any_nan : Bool
  found : Array[Int32]
}

///|
fn Region::new(
  pts : Points,
  max_distance : Double,
  trig : @core.Trig,
) -> Region {
  let n = pts.xs.length()
  let mut any_nan = false
  for i in 0..<n {
    if is_nan(pts.xs[i]) || is_nan(pts.ys[i]) {
      any_nan = true
    }
  }
  let ids = Array::makei(n, i => i)
  if !any_nan {
    ids.sort_by((a, b) => pts.xs[a].compare(pts.xs[b]))
  }
  let order = FixedArray::makei(n, i => ids[i])
  {
    pts,
    trig,
    max_distance,
    lat_degrees: max_distance / km_factor % (2.0 * PI) * 180.0 / PI,
    order,
    sorted_x: FixedArray::makei(n, i => pts.xs[order[i]]),
    cos_lat: FixedArray::makei(n, i => trig.cos(radians(pts.ys[i]))),
    any_nan,
    found: [],
  }
}

///|
/// `@turf/distance` from point `i` to point `j`, in kilometers.
fn Region::distance(self : Region, i : Int32, j : Int32) -> Double {
  let trig = self.trig
  let d_lat = radians(self.pts.ys[j] - self.pts.ys[i])
  let d_lon = radians(self.pts.xs[j] - self.pts.xs[i])
  let a = trig.pow(trig.sin(d_lat / 2.0), 2.0) +
    trig.pow(trig.sin(d_lon / 2.0), 2.0) * self.cos_lat[i] * self.cos_lat[j]
  2.0 * trig.atan2(a.sqrt(), (1.0 - a).sqrt()) * km_factor
}

///|
/// Turf's `regionQuery` into `self.found`. A NaN coordinate anywhere makes
/// rbush's root box NaN, which no search box meets.
fn Region::query(self : Region, i : Int32) -> Unit {
  self.found.clear()
  guard !self.any_nan else { return }
  let x = self.pts.xs[i]
  let y = self.pts.ys[i]
  let lat = self.lat_degrees
  let min_y = js_max(y - lat, -90.0)
  let max_y = js_min(y + lat, 90.0)
  let lon = if min_y < 0.0 && max_y > 0.0 {
    lat
  } else if min_y.abs() < max_y.abs() {
    lat / self.trig.cos(radians(max_y))
  } else {
    lat / self.trig.cos(radians(min_y))
  }
  let min_x = js_max(x - lon, -360.0)
  let max_x = js_min(x + lon, 360.0)
  guard min_x <= max_x && min_y <= max_y else { return }
  let sorted = self.sorted_x
  let mut lo = 0
  let mut hi = sorted.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if sorted[mid] < min_x {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  for k = lo; k < sorted.length() && sorted[k] <= max_x; k = k + 1 {
    let j = self.order[k]
    let yj = self.pts.ys[j]
    if yj >= min_y && yj <= max_y && self.distance(i, j) <= self.max_distance {
      self.found.push(j)
    }
  }
}

///|
/// `@turf/clusters-dbscan` over `t`'s Point rows, `max_distance` in
/// kilometers: two ints per row, Turf's `properties.cluster` (-1 when it has
/// none) and its `properties.dbscan` as `DBSCAN_CORE`, `DBSCAN_EDGE`,
/// `DBSCAN_NOISE` (or `DBSCAN_SKIPPED` for other rows, which take no part).
/// `min_points` 0 is Turf's default, 3. None past `MAX_CLUSTER_POINTS`.
pub fn dbscan_checked(
  t : @geom.Table,
  max_distance : Double,
  min_points : Int32,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> FixedArray[Int32]? {
  guard points_of(t) is Some(pts) else { return None }
  let out = skipped(t)
  let n = pts.rows.length()
  let min_points = if min_points == 0 { 3 } else { min_points }
  let region = Region::new(pts, max_distance, trig)
  let visited = FixedArray::make(n, false)
  let noise = FixedArray::make(n, false)
  let queued = FixedArray::make(n, false)
  let cluster = FixedArray::make(n, -1)
  // Turf's `expandCluster` queues neighbors again and again; an index queued
  // before is visited and assigned by then, so each is queued once here.
  let queue : Array[Int32] = []
  let enqueue = () => {
    for j in region.found {
      if !queued[j] {
        queued[j] = true
        queue.push(j)
      }
    }
  }
  let mut next_id = 0
  for i in 0..<n {
    if visited[i] {
      continue
    }
    region.query(i)
    if region.found.length() < min_points {
      noise[i] = true
      continue
    }
    let id = next_id
    next_id += 1
    visited[i] = true
    queue.clear()
    enqueue()
    for h = 0; h < queue.length(); h = h + 1 {
      let j = queue[h]
      if !visited[j] {
        visited[j] = true
        region.query(j)
        if region.found.length() >= min_points {
          enqueue()
        }
      }
      cluster[j] = id
    }
  }
  for i in 0..<n {
    let row = pts.rows[i]
    out[2 * row] = cluster[i]
    out[2 * row + 1] = if cluster[i] < 0 {
      DBSCAN_NOISE
    } else if noise[i] {
      DBSCAN_EDGE
    } else {
      DBSCAN_CORE
    }
  }
  Some(out)
}

///|
/// `dbscan_checked`, with every row `DBSCAN_SKIPPED` past `MAX_CLUSTER_POINTS`.
pub fn dbscan(
  t : @geom.Table,
  max_distance : Double,
  min_points : Int32,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> FixedArray[Int32] {
  match dbscan_checked(t, max_distance, min_points, trig~) {
    Some(out) => out
    None => skipped(t)
  }
}

///|
fn skipped(t : @geom.Table) -> FixedArray[Int32] {
  FixedArray::makei(2 * t.length(), i => {
    if i % 2 == 0 {
      -1
    } else {
      DBSCAN_SKIPPED
    }
  })
}
