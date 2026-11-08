///|
/// Where a buffer's distance is measured: `Geodesic` on the ground (coordinates
/// in degrees, each feature in a plane true to distances from its center), or
/// `Planar` in the coordinates' own plane (a projected CRS's meters).
pub(all) enum BufferMode {
  Geodesic
  Planar
}

///|
/// Longest input edge buffered as is, in degrees (about 1 km): longer ones are
/// split so they follow their straight line in longitude and latitude.
const BUFFER_DENSIFY : Double = 0.01

///|
fn degree_int(lon : Double, lat : Double) -> @clipper.Point64 {
  {
    x: (lon * DEGREE_SCALE).round().to_int64(),
    y: (lat * DEGREE_SCALE).round().to_int64(),
  }
}

///|
fn degree_xy(p : @clipper.Point64) -> (Double, Double) {
  (p.x.to_double() / DEGREE_SCALE, p.y.to_double() / DEGREE_SCALE)
}

///|
/// Feature `f`'s bounding box: west, south, east, north (None without points).
fn bbox_of(t : @geom.Table, f : Int32) -> (Double, Double, Double, Double)? {
  let (i0, i1) = t.feature_points(f)
  if i0 == i1 {
    return None
  }
  let mut w = t.coords[i0 * 2]
  let mut s = t.coords[i0 * 2 + 1]
  let mut e = w
  let mut n = s
  for i in i0..<i1 {
    let x = t.coords[i * 2]
    let y = t.coords[i * 2 + 1]
    w = @cmp.minimum(w, x)
    e = @cmp.maximum(e, x)
    s = @cmp.minimum(s, y)
    n = @cmp.maximum(n, y)
  }
  Some((w, s, e, n))
}

///|
fn copy_props(
  b : @geom.TableBuilder,
  t : @geom.Table,
  f : Int32,
  suffix~ : String = "",
  taken? : Array[String],
) -> Unit {
  for c in t.columns {
    if c.values[f] is Some(v) {
      let name = match taken {
        Some(names) if names.contains(c.name) => c.name + suffix
        _ => c.name
      }
      b.prop(name, v)
    }
  }
}

///|
fn polygon_kind(parts : Int32) -> @geom.GeomKind {
  if parts == 1 {
    Polygon
  } else {
    MultiPolygon
  }
}

///|
/// Appends open paths as parts of one ring each; how many.
fn add_lines(
  b : @geom.TableBuilder,
  lines : Array[Array[@clipper.Point64]],
  to_xy : (@clipper.Point64) -> (Double, Double),
) -> Int32 {
  for line in lines {
    for pt in line {
      let (x, y) = to_xy(pt)
      b.point(x, y)
    }
    b.end_ring()
    b.end_part()
  }
  lines.length()
}

///|
/// A tree of `paths` (already non-overlapping) nesting holes in outers.
fn tree_of(paths : Array[Array[@clipper.Point64]]) -> @clipper.PolyPath64 {
  let c = @clipper.Clipper64::new()
  c.add_subject(paths)
  match c.execute_tree(Union, NonZero) {
    Some((root, _)) => root
    None => @clipper.PolyPath64::new()
  }
}

///|
/// Every feature of `t` grown by `meters` (shrunk if negative; lines and points
/// only grow) as polygons with its properties, shaped by `join`, `cap` and
/// `arc_tolerance` (meters, 0 for distance / 500); vanished ones keep their row.
pub fn buffer(
  t : @geom.Table,
  meters : Double,
  mode~ : BufferMode = Geodesic,
  join~ : @clipper.JoinType = Round,
  cap~ : @clipper.EndType = Round,
  arc_tolerance~ : Double = 0.0,
) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for f in 0..<t.length() {
    let (fwd, inv, densify) : (
      (Double, Double) -> (Double, Double),
      (Double, Double) -> (Double, Double),
      Double,
    ) = match (mode, bbox_of(t, f)) {
      (Geodesic, Some((w, s, e, n))) => {
        let plane = LocalPlane::new((w + e) / 2.0, (s + n) / 2.0)
        (
          (x, y) => plane.forward(x, y),
          (x, y) => plane.inverse(x, y),
          BUFFER_DENSIFY,
        )
      }
      _ => ((x, y) => (x, y), (x, y) => (x, y), 0.0)
    }
    let to_int = (lon : Double, lat : Double) => {
      let (x, y) = fwd(lon, lat)
      (
        {
          x: (x * METER_SCALE).round().to_int64(),
          y: (y * METER_SCALE).round().to_int64(),
        } : @clipper.Point64)
    }
    let to_xy = (p : @clipper.Point64) => {
      inv(p.x.to_double() / METER_SCALE, p.y.to_double() / METER_SCALE)
    }
    let shape = shape_of(t, f, to_int, densify~)
    let o = @clipper.ClipperOffset::new(
      arc_tolerance=arc_tolerance * METER_SCALE,
    )
    o.add_paths(normalized(shape.polygons), join, Polygon)
    o.add_paths(shape.lines, join, cap)
    o.add_paths(shape.points.map(p => [p]), join, Polygon)
    let parts = add_tree(b, tree_of(o.execute(meters * METER_SCALE)), to_xy)
    copy_props(b, t, f)
    b.end_feature(polygon_kind(parts), id=t.ids[f])
  }
  b.finish()
}

///|
/// The polygons of every feature of `t` merged into one feature without
/// properties (lines and points are left out).
pub fn dissolve(t : @geom.Table) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  let parts = add_tree(b, tree_of(region_of(t)), degree_xy)
  b.end_feature(polygon_kind(parts))
  b.finish()
}

///|
/// The area covered by the polygons of `t`, as oriented non-overlapping rings.
fn region_of(t : @geom.Table) -> Array[Array[@clipper.Point64]] {
  let all = []
  for f in 0..<t.length() {
    for ring in normalized(shape_of(t, f, degree_int).polygons) {
      all.push(ring)
    }
  }
  @clipper.union(all, [], NonZero)
}

///|
/// Whether `pt` lies in `region` (non-overlapping oriented rings) or on its edge.
fn in_region(
  pt : @clipper.Point64,
  region : Array[Array[@clipper.Point64]],
) -> Bool {
  let mut inside = false
  for ring in region {
    match @clipper.point_in_polygon(pt, ring[:]) {
      IsOn => return true
      IsInside => inside = !inside
      IsOutside => ()
    }
  }
  inside
}

///|
/// Appends `shape` cut by `region` with `op` (`Intersection` or
/// `Difference`) as one feature's geometry: its kind, or None if nothing is left.
fn cut(
  b : @geom.TableBuilder,
  shape : Shape,
  region : Array[Array[@clipper.Point64]],
  op : @clipper.ClipType,
) -> @geom.GeomKind? {
  if shape.points.length() > 0 {
    let keep = shape.points.filter(p => {
      in_region(p, region) == (op == Intersection)
    })
    for p in keep {
      let (x, y) = degree_xy(p)
      b.point(x, y)
    }
    b.end_ring()
    b.end_part()
    return match keep.length() {
      0 => None
      1 => Some(Point)
      _ => Some(MultiPoint)
    }
  }
  let c = @clipper.Clipper64::new()
  c.add_subject(normalized(shape.polygons))
  c.add_open_subject(shape.lines)
  c.add_clip(region)
  guard c.execute_tree(op, NonZero) is Some((root, open)) else { return None }
  if shape.lines.length() > 0 {
    match add_lines(b, open, degree_xy) {
      0 => None
      1 => Some(LineString)
      _ => Some(MultiLineString)
    }
  } else {
    match add_tree(b, root, degree_xy) {
      0 => None
      n => Some(polygon_kind(n))
    }
  }
}

///|
/// A path's bounding box in Clipper integers: min x, min y, max x, max y.
fn path_box(path : Array[@clipper.Point64]) -> (Int64, Int64, Int64, Int64) {
  let mut x0 = @int64.MAX_VALUE
  let mut y0 = @int64.MAX_VALUE
  let mut x1 = @int64.MIN_VALUE
  let mut y1 = @int64.MIN_VALUE
  for p in path {
    x0 = @cmp.minimum(x0, p.x)
    y0 = @cmp.minimum(y0, p.y)
    x1 = @cmp.maximum(x1, p.x)
    y1 = @cmp.maximum(y1, p.y)
  }
  (x0, y0, x1, y1)
}

///|
/// The bounding box (as `path_box`) of every path and point of `shape`.
fn shape_box(shape : Shape) -> (Int64, Int64, Int64, Int64) {
  let grow = (
    a : (Int64, Int64, Int64, Int64),
    b : (Int64, Int64, Int64, Int64),
  ) => {
    (
      @cmp.minimum(a.0, b.0),
      @cmp.minimum(a.1, b.1),
      @cmp.maximum(a.2, b.2),
      @cmp.maximum(a.3, b.3),
    )
  }
  let mut box = path_box(shape.points)
  for p in shape.polygons {
    box = grow(box, path_box(p))
  }
  for l in shape.lines {
    box = grow(box, path_box(l))
  }
  box
}

///|
fn cut_all(
  a : @geom.Table,
  b : @geom.Table,
  op : @clipper.ClipType,
) -> @geom.Table {
  let region = region_of(b)
  let boxes = region.map(path_box)
  let out = @geom.TableBuilder::new()
  for f in 0..<a.length() {
    let shape = shape_of(a, f, degree_int)
    // Only the region's rings that reach the feature matter: a hole lies in
    // its outer ring, so dropping rings away from the feature keeps the rest
    // paired.
    let (x0, y0, x1, y1) = shape_box(shape)
    let near = []
    for i, ring in region {
      let (rx0, ry0, rx1, ry1) = boxes[i]
      if rx0 <= x1 && x0 <= rx1 && ry0 <= y1 && y0 <= ry1 {
        near.push(ring)
      }
    }
    match cut(out, shape, near, op) {
      Some(kind) => {
        copy_props(out, a, f)
        out.end_feature(kind, id=a.ids[f])
      }
      None => out.discard_feature()
    }
  }
  out.finish()
}

///|
/// The features of `a` cut to the area of `b`'s polygons, keeping `a`'s
/// properties; features left empty are dropped.
pub fn clip(a : @geom.Table, b : @geom.Table) -> @geom.Table {
  cut_all(a, b, Intersection)
}

///|
/// The features of `a` with the area of `b`'s polygons removed, keeping `a`'s
/// properties; features left empty are dropped.
pub fn erase(a : @geom.Table, b : @geom.Table) -> @geom.Table {
  cut_all(a, b, Difference)
}

///|
/// The overlay of `a` with `b`'s polygons: one feature per overlapping pair,
/// its part of the `a` feature, with the properties of both (`b`'s keys that
/// `a` also has get the suffix `_2`).
pub fn intersect(a : @geom.Table, b : @geom.Table) -> @geom.Table {
  let names = a.columns.map(c => c.name)
  let regions = Array::makei(b.length(), g => {
    normalized(shape_of(b, g, degree_int).polygons)
  })
  let boxes = Array::makei(b.length(), g => bbox_of(b, g))
  let out = @geom.TableBuilder::new()
  for f in 0..<a.length() {
    guard bbox_of(a, f) is Some((w, s, e, n)) else { continue }
    let shape = shape_of(a, f, degree_int)
    for g in 0..<b.length() {
      guard boxes[g] is Some((w2, s2, e2, n2)) &&
        regions[g].length() > 0 &&
        w <= e2 &&
        w2 <= e &&
        s <= n2 &&
        s2 <= n else {
        continue
      }
      match cut(out, shape, regions[g], Intersection) {
        Some(kind) => {
          copy_props(out, a, f)
          copy_props(out, b, g, suffix="_2", taken=names)
          out.end_feature(kind)
        }
        None => out.discard_feature()
      }
    }
  }
  out.finish()
}
