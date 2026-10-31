// Ported from @maplibre/geojson-vt 6.3.0: MIT License, Copyright (c) 2025
// MapLibre contributors, and ISC License, Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// Projected features (geojson-vt's internal features) in columns. Each
/// conversion or clip writes the features it makes into a store of its own;
/// a feature kept whole is shared by reference (`FRef`), as geojson-vt
/// shares the object, and a store is freed once nothing refers to it.
/// Feature `f` spans parts
/// `part_ends[f - 1]..<part_ends[f]` and so on down to points, which are
/// x, y and simplification importance triples in `pts`. `kind` is 1 for
/// points, 2 for lines (a part is a line) and 3 for polygons (a part is a
/// polygon: exterior ring, then holes). `size` is a ring's length (lines)
/// or area (polygons) in world units, used to drop rings too small to show.
priv struct Store {
  kind : Array[Int32]
  row : Array[Int32]
  min_x : Array[Double]
  min_y : Array[Double]
  max_x : Array[Double]
  max_y : Array[Double]
  part_ends : Array[Int32]
  ring_ends : Array[Int32]
  point_ends : Array[Int32]
  size : Array[Double]
  pts : Array[Double]
}

///|
fn Store::new() -> Store {
  {
    kind: [],
    row: [],
    min_x: [],
    min_y: [],
    max_x: [],
    max_y: [],
    part_ends: [],
    ring_ends: [],
    point_ends: [],
    size: [],
    pts: [],
  }
}

///|
fn last_or_zero(a : Array[Int32]) -> Int32 {
  match a.last() {
    Some(v) => v
    None => 0
  }
}

///|
fn start(ends : Array[Int32], i : Int32) -> Int32 {
  if i == 0 {
    0
  } else {
    ends[i - 1]
  }
}

///|
fn Store::push_point(self : Store, x : Double, y : Double, z : Double) -> Unit {
  self.pts.push(x)
  self.pts.push(y)
  self.pts.push(z)
}

///|
/// Points pushed since the last ring.
fn Store::open_points(self : Store) -> Int32 {
  self.pts.length() / 3 - last_or_zero(self.point_ends)
}

///|
/// Closes the ring of points pushed since the last one, if any.
fn Store::end_ring(self : Store, size : Double) -> Unit {
  if self.open_points() > 0 {
    self.point_ends.push(self.pts.length() / 3)
    self.size.push(size)
  }
}

///|
/// Closes the part of rings closed since the last one, if any.
fn Store::end_part(self : Store) -> Unit {
  if self.point_ends.length() > last_or_zero(self.ring_ends) {
    self.ring_ends.push(self.point_ends.length())
  }
}

///|
/// Closes the feature of parts closed since the last one and returns its
/// index, or drops what was pushed for it and returns -1 if it is empty.
/// The box follows geojson-vt's `createFeature`: all points of points and
/// lines, but only each polygon's first ring.
fn Store::end_feature(self : Store, kind : Int32, row : Int32) -> Int32 {
  let p0 = last_or_zero(self.part_ends)
  let p1 = self.ring_ends.length()
  if p1 == p0 {
    let r = last_or_zero(self.ring_ends)
    self.point_ends.truncate(r)
    self.size.truncate(r)
    self.pts.truncate(last_or_zero(self.point_ends) * 3)
    return -1
  }
  let mut x0 = @double.infinity
  let mut y0 = @double.infinity
  let mut x1 = @double.neg_infinity
  let mut y1 = @double.neg_infinity
  for p in p0..<p1 {
    let r0 = start(self.ring_ends, p)
    let r1 = if kind == 3 { r0 + 1 } else { self.ring_ends[p] }
    for r in r0..<r1 {
      for i in start(self.point_ends, r)..<self.point_ends[r] {
        let x = self.pts[i * 3]
        let y = self.pts[i * 3 + 1]
        x0 = @cmp.minimum(x0, x)
        y0 = @cmp.minimum(y0, y)
        x1 = @cmp.maximum(x1, x)
        y1 = @cmp.maximum(y1, y)
      }
    }
  }
  self.kind.push(kind)
  self.row.push(row)
  self.min_x.push(x0)
  self.min_y.push(y0)
  self.max_x.push(x1)
  self.max_y.push(y1)
  self.part_ends.push(p1)
  self.kind.length() - 1
}

///|
/// A feature: its index in the store that holds it.
priv struct FRef {
  s : Store
  i : Int32
}
