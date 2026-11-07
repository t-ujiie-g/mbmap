///|
/// Most points `triangles_checked` and `voronoi_checked` take (AGENTS.md §8.2).
pub const MAX_DELAUNAY_POINTS : Int32 = 1_000_000

///|
/// The points of every Point and MultiPoint row in table order, with the row
/// each came from; other kinds contribute none.
fn table_points(t : @geom.Table) -> (Array[Double], Array[Int32]) {
  let xy = []
  let rows = []
  for f in 0..<t.length() {
    match t.kinds[f] {
      Point | MultiPoint => ()
      _ => continue
    }
    let (p0, p1) = t.parts(f)
    for p in p0..<p1 {
      let (r0, r1) = t.rings(p)
      for r in r0..<r1 {
        let (c0, c1) = t.points(r)
        for c in c0..<c1 {
          xy.push(t.coords[c * 2])
          xy.push(t.coords[c * 2 + 1])
          rows.push(f)
        }
      }
    }
  }
  (xy, rows)
}

///|
/// d3-delaunay's triangulation of the finite points among `xy`, and for each
/// point its index there (-1 for a point with a non-finite coordinate).
fn triangulate(
  xy : Array[Double],
  trig : @core.Trig,
) -> (Delaunay, Array[Int32]) {
  let index = []
  let mut kept = 0
  for k in 0..<(xy.length() / 2) {
    if !finite(xy[2 * k]) || !finite(xy[2 * k + 1]) {
      index.push(-1)
    } else {
      index.push(kept)
      kept += 1
    }
  }
  let points = FixedArray::make(kept * 2, 0.0)
  for k, i in index {
    if i >= 0 {
      points[2 * i] = xy[2 * k]
      points[2 * i + 1] = xy[2 * k + 1]
    }
  }
  (Delaunay::new(points, trig), index)
}

///|
/// d3-delaunay's `trianglePolygons()` of the Point and MultiPoint rows' finite
/// points (collinear ones jittered through `trig`), a Polygon row each; fewer
/// than three distinct points make no rows.
pub fn triangles(
  t : @geom.Table,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> @geom.Table {
  let (xy, _) = table_points(t)
  let (d, _) = triangulate(xy, trig)
  let b = @geom.TableBuilder::new()
  if d.hull.length() > 2 {
    for i in 0..<(d.triangles.length() / 3) {
      let (x0, y0, x1, y1, x2, y2) = d.triangle_points(i)
      b.point(x0, y0)
      b.point(x1, y1)
      b.point(x2, y2)
      b.point(x0, y0)
      b.end_ring()
      b.end_part()
      b.end_feature(Polygon)
    }
  }
  b.finish()
}

///|
/// `triangles`, or None for more than `MAX_DELAUNAY_POINTS` points.
pub fn triangles_checked(
  t : @geom.Table,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> @geom.Table? {
  if point_count(t) > MAX_DELAUNAY_POINTS {
    None
  } else {
    Some(triangles(t, trig~))
  }
}

///|
/// d3-delaunay's `cellPolygon(i)` within the bounds for each point of the Point
/// and MultiPoint rows, with its row's id and properties; no geometry for a null
/// or non-finite cell, a non-finite point or bounds d3-delaunay refuses.
pub fn voronoi(
  t : @geom.Table,
  xmin : Double,
  ymin : Double,
  xmax : Double,
  ymax : Double,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> @geom.Table {
  let (xy, rows) = table_points(t)
  let b = @geom.TableBuilder::new()
  let valid = finite(xmin) &&
    finite(ymin) &&
    finite(xmax) &&
    finite(ymax) &&
    xmax >= xmin &&
    ymax >= ymin
  let (cells, index) = if valid {
    let (d, index) = triangulate(xy, trig)
    (Some(Voronoi::new(d, xmin, ymin, xmax, ymax)), index)
  } else {
    (None, [])
  }
  for k, f in rows {
    if cells is Some(v) &&
      index[k] >= 0 &&
      v.cell_polygon(index[k]) is Some(ring) &&
      ring.iter().all(finite) {
      for c = 0; c < ring.length(); c = c + 2 {
        b.point(ring[c], ring[c + 1])
      }
      b.end_ring()
      b.end_part()
    }
    for c in t.columns {
      if c.values[f] is Some(v) {
        b.prop(c.name, v)
      }
    }
    b.end_feature(Polygon, id=t.ids[f])
  }
  b.finish()
}

///|
/// `voronoi`, or None for more than `MAX_DELAUNAY_POINTS` points.
pub fn voronoi_checked(
  t : @geom.Table,
  xmin : Double,
  ymin : Double,
  xmax : Double,
  ymax : Double,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> @geom.Table? {
  if point_count(t) > MAX_DELAUNAY_POINTS {
    None
  } else {
    Some(voronoi(t, xmin, ymin, xmax, ymax, trig~))
  }
}

///|
fn finite(v : Double) -> Bool {
  !v.is_nan() && !v.is_inf()
}

///|
fn point_count(t : @geom.Table) -> Int32 {
  let mut n = 0
  for f in 0..<t.length() {
    if t.kinds[f] is (Point | MultiPoint) {
      let (p0, p1) = t.parts(f)
      if p0 < p1 {
        let (r0, _) = t.rings(p0)
        let (_, r1) = t.rings(p1 - 1)
        if r0 < r1 {
          n += t.points(r1 - 1).1 - t.points(r0).0
        }
      }
    }
  }
  n
}
