// Ported from @maplibre/geojson-vt 6.3.0: MIT License, Copyright (c) 2025
// MapLibre contributors, and ISC License, Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// geojson-vt's projected features, nested like `@geom.Table`: `pts` as (x, y,
/// importance), `size` a ring's length or area, `from`/`to` a line slice's place
/// along it. Each conversion or clip has its own store (`FRef` shares features).
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
  from : Array[Double]
  to : Array[Double]
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
    from: [],
    to: [],
    pts: [],
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
  self.pts.length() / 3 - @geom.start_of_last(self.point_ends)
}

///|
/// Closes the ring of points pushed since the last one, if any; a line's slice
/// lies from `from` to `to` along it (all of it by default).
fn Store::end_ring(
  self : Store,
  size : Double,
  from~ : Double = 0.0,
  to~ : Double = size,
) -> Unit {
  if self.open_points() > 0 {
    self.point_ends.push(self.pts.length() / 3)
    self.size.push(size)
    self.from.push(from)
    self.to.push(to)
  }
}

///|
/// Closes the part of rings closed since the last one, if any.
fn Store::end_part(self : Store) -> Unit {
  if self.point_ends.length() > @geom.start_of_last(self.ring_ends) {
    self.ring_ends.push(self.point_ends.length())
  }
}

///|
/// Closes the feature and returns its index, or -1 (dropping it) if empty.
/// Like geojson-vt's `createFeature`, a polygon's box covers its first ring only.
fn Store::end_feature(self : Store, kind : Int32, row : Int32) -> Int32 {
  let p0 = @geom.start_of_last(self.part_ends)
  let p1 = self.ring_ends.length()
  if p1 == p0 {
    let r = @geom.start_of_last(self.ring_ends)
    self.point_ends.truncate(r)
    self.size.truncate(r)
    self.from.truncate(r)
    self.to.truncate(r)
    self.pts.truncate(@geom.start_of_last(self.point_ends) * 3)
    return -1
  }
  let mut x0 = @double.infinity
  let mut y0 = @double.infinity
  let mut x1 = @double.neg_infinity
  let mut y1 = @double.neg_infinity
  for p in p0..<p1 {
    let r0 = @geom.start_of(self.ring_ends, p)
    let r1 = if kind == @core.GEOM_POLYGONS {
      r0 + 1
    } else {
      self.ring_ends[p]
    }
    for r in r0..<r1 {
      for i in @geom.start_of(self.point_ends, r)..<self.point_ends[r] {
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
