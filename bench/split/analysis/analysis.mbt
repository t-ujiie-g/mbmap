///|
/// Mean Earth radius in meters (WGS 84), as Turf.js uses for areas.
pub const EARTH_RADIUS : Double = 6371008.8

///|
/// Columnar polygons: `coords` holds lng, lat pairs in degrees; ring `r`
/// spans points `ring_ends[r - 1]..<ring_ends[r]`; polygon `p` spans rings
/// `poly_ends[p - 1]..<poly_ends[p]`, the first one its exterior.
pub(all) struct Polygons {
  coords : FixedArray[Double]
  ring_ends : FixedArray[Int32]
  poly_ends : FixedArray[Int32]
}

///|
pub fn Polygons::length(self : Polygons) -> Int32 {
  self.poly_ends.length()
}

///|
fn radians(d : Double) -> Double {
  d * @math.PI / 180.0
}

///|
/// Area of one ring on the sphere in square meters (unsigned), with the
/// formula Turf.js uses (Chamberlain and Duquette).
fn ring_area(coords : FixedArray[Double], start : Int32, end : Int32) -> Double {
  let n = end - start
  if n < 3 {
    return 0.0
  }
  let mut total = 0.0
  for i in 0..<n {
    let a = start + i
    let b = start + (i + 1) % n
    let c = start + (i + 2) % n
    total += (radians(coords[c * 2]) - radians(coords[a * 2])) *
      @math.sin(radians(coords[b * 2 + 1]))
  }
  (total * EARTH_RADIUS * EARTH_RADIUS / 2.0).abs()
}

///|
/// Area of polygon `p` in square meters: the exterior minus its holes.
pub fn Polygons::area(self : Polygons, p : Int32) -> Double {
  let first = if p == 0 { 0 } else { self.poly_ends[p - 1] }
  let mut area = 0.0
  for r in first..<self.poly_ends[p] {
    let start = if r == 0 { 0 } else { self.ring_ends[r - 1] }
    let a = ring_area(self.coords, start, self.ring_ends[r])
    area += if r == first { a } else { -a }
  }
  area
}

///|
/// Bounding box of polygon `p` as (west, south, east, north).
pub fn Polygons::bbox(
  self : Polygons,
  p : Int32,
) -> (Double, Double, Double, Double) {
  let first = if p == 0 { 0 } else { self.poly_ends[p - 1] }
  let start = if first == 0 { 0 } else { self.ring_ends[first - 1] }
  let end = self.ring_ends[first]
  let mut w = 180.0
  let mut s = 90.0
  let mut e = -180.0
  let mut n = -90.0
  for i in start..<end {
    let x = self.coords[i * 2]
    let y = self.coords[i * 2 + 1]
    w = @cmp.minimum(w, x)
    e = @cmp.maximum(e, x)
    s = @cmp.minimum(s, y)
    n = @cmp.maximum(n, y)
  }
  (w, s, e, n)
}

///|
/// How many polygons have their bbox center in each `cell`-degree grid cell,
/// keyed by `row * 65536 + column`.
pub fn Polygons::grid_counts(
  self : Polygons,
  cell : Double,
) -> Map[Int32, Int32] {
  let counts : Map[Int32, Int32] = Map([])
  for p in 0..<self.length() {
    let (w, s, e, n) = self.bbox(p)
    let col = ((w + e) / 2.0 / cell).floor().to_int()
    let row = ((s + n) / 2.0 / cell).floor().to_int()
    let key = row * 65536 + col
    counts[key] = counts.get(key).unwrap_or(0) + 1
  }
  counts
}

///|
/// Indices of the `k` largest polygons by area, largest first.
pub fn Polygons::largest(self : Polygons, k : Int32) -> Array[Int32] {
  let areas = Array::makei(self.length(), p => (p, self.area(p)))
  areas.sort_by((a, b) => b.1.compare(a.1))
  areas[:@cmp.minimum(k, areas.length())].iter().map(x => x.0).collect()
}

///|
/// A one-line summary, for the error and logging paths that real analysis
/// code has.
pub fn Polygons::describe(self : Polygons) -> String {
  "\{self.length()} polygons, \{self.ring_ends.length()} rings, \{self.coords.length() / 2} points"
}
