///|
/// Most points `relate_checked` takes from both rows together.
pub const MAX_RELATE_POINTS : Int32 = 1_000_000

///|
/// The DE-9IM matrix of row `i` of `a` against row `j` of `b`, as JTS's
/// `RelateOp.relate` with the OGC SFS (mod-2) boundary rule. A row out of
/// range or without points is an empty geometry.
pub fn relate(a : @geom.Table, i : Int32, b : @geom.Table, j : Int32) -> Matrix {
  compute_im(Geometry::of_row(a, i), Geometry::of_row(b, j), { failed: false, })
}

///|
/// The points rows `i` of `a` and `j` of `b` hold together.
pub fn pair_points(
  a : @geom.Table,
  i : Int32,
  b : @geom.Table,
  j : Int32,
) -> Int32 {
  Geometry::point_count(a, i) + Geometry::point_count(b, j)
}

///|
/// Whether rows `i` of `a` and `j` of `b` hold at most `MAX_RELATE_POINTS`
/// points together.
pub fn within_limit(
  a : @geom.Table,
  i : Int32,
  b : @geom.Table,
  j : Int32,
) -> Bool {
  pair_points(a, i, b, j) <= MAX_RELATE_POINTS
}

///|
/// `relate`, or None when the rows hold more than `MAX_RELATE_POINTS` points
/// together, or when they are invalid in a way that makes JTS throw (a
/// topology or assertion error); `relate` then gives its best effort.
pub fn relate_checked(
  a : @geom.Table,
  i : Int32,
  b : @geom.Table,
  j : Int32,
) -> Matrix? {
  if !within_limit(a, i, b, j) {
    return None
  }
  let status = { failed: false, }
  let im = compute_im(Geometry::of_row(a, i), Geometry::of_row(b, j), status)
  if status.failed {
    None
  } else {
    Some(im)
  }
}

///|
/// The dimension of row `i`'s geometry: 0 for points, 1 for lines, 2 for
/// polygons, -1 when empty.
pub fn dimension(t : @geom.Table, i : Int32) -> Int32 {
  Geometry::of_row(t, i).dimension()
}

///|
/// The JTS predicate `name` (as JSTS's `Geometry` methods answer it, "equals"
/// being `equalsTopo`, "disjoint" included) of row `i` of `a` against row `j` of
/// `b`; false for any other name.
pub fn predicate(
  a : @geom.Table,
  i : Int32,
  b : @geom.Table,
  j : Int32,
  name : String,
) -> Bool {
  let g1 = Geometry::of_row(a, i)
  let g2 = Geometry::of_row(b, j)
  match name {
    "intersects" => intersects(g1, g2)
    "disjoint" => !intersects(g1, g2)
    "contains" => contains(g1, g2)
    "within" => contains(g2, g1)
    "covers" => covers(g1, g2)
    "coveredBy" => covers(g2, g1)
    "touches" =>
      g1.env().intersects(g2.env()) &&
      im_of(g1, g2).is_touches(g1.dimension(), g2.dimension())
    "crosses" =>
      g1.env().intersects(g2.env()) &&
      im_of(g1, g2).is_crosses(g1.dimension(), g2.dimension())
    "overlaps" =>
      g1.env().intersects(g2.env()) &&
      im_of(g1, g2).is_overlaps(g1.dimension(), g2.dimension())
    "equals" =>
      g1.env().equals(g2.env()) &&
      im_of(g1, g2).is_equals(g1.dimension(), g2.dimension())
    _ => false
  }
}

///|
fn im_of(g1 : Geometry, g2 : Geometry) -> Matrix {
  compute_im(g1, g2, { failed: false, })
}

///|
/// `RelateOp.intersects`.
fn intersects(g1 : Geometry, g2 : Geometry) -> Bool {
  if !g1.env().intersects(g2.env()) {
    return false
  }
  if g1.is_rectangle() {
    return rectangle_intersects(g1, g2)
  }
  if g2.is_rectangle() {
    return rectangle_intersects(g2, g1)
  }
  im_of(g1, g2).is_intersects()
}

///|
/// The dimension rules `RelateOp.contains` and `covers` start with.
fn cannot_contain(g1 : Geometry, g2 : Geometry) -> Bool {
  (g2.dimension() == 2 && g1.dimension() < 2) ||
  (g2.dimension() == 1 && g1.dimension() < 1 && g2.length() > 0.0)
}

///|
fn contains(g1 : Geometry, g2 : Geometry) -> Bool {
  if cannot_contain(g1, g2) || !g1.env().covers(g2.env()) {
    return false
  }
  if g1.is_rectangle() {
    return rectangle_contains(g1, g2)
  }
  im_of(g1, g2).is_contains()
}

///|
fn covers(g1 : Geometry, g2 : Geometry) -> Bool {
  if cannot_contain(g1, g2) || !g1.env().covers(g2.env()) {
    return false
  }
  if g1.is_rectangle() {
    return true
  }
  im_of(g1, g2).is_covers()
}

///|
/// `Polygon.isRectangle`: a hole-free shell of five points on its envelope's
/// sides, each step moving along one axis.
fn Geometry::is_rectangle(self : Geometry) -> Bool {
  if self.kind != Poly || self.polys[0].length() != 1 {
    return false
  }
  let ring = self.polys[0][0]
  if ring.length() != 5 {
    return false
  }
  let env = self.env()
  for p in ring {
    if !(p.x == env.minx || p.x == env.maxx) {
      return false
    }
    if !(p.y == env.miny || p.y == env.maxy) {
      return false
    }
  }
  for i in 1..<=4 {
    let x_changed = ring[i].x != ring[i - 1].x
    let y_changed = ring[i].y != ring[i - 1].y
    if x_changed == y_changed {
      return false
    }
  }
  true
}

///|
/// `RectangleContains.contains`.
fn rectangle_contains(rect : Geometry, g : Geometry) -> Bool {
  let env = rect.env()
  if !env.covers(g.env()) {
    return false
  }
  let on_boundary = fn(p : Coord) {
    p.x == env.minx || p.x == env.maxx || p.y == env.miny || p.y == env.maxy
  }
  let in_boundary = match g.kind {
    Poly | MultiPoly => g.polys.length() == 0
    Empty => true
    Point | MultiPoint => g.points.iter().all(on_boundary)
    Line | MultiLine =>
      g.lines
      .iter()
      .all(fn(l) {
        for k in 0..<(l.length() - 1) {
          let p0 = l[k]
          let p1 = l[k + 1]
          let ok = if p0.eq2d(p1) {
            on_boundary(p0)
          } else if p0.x == p1.x {
            p0.x == env.minx || p0.x == env.maxx
          } else if p0.y == p1.y {
            p0.y == env.miny || p0.y == env.maxy
          } else {
            false
          }
          if !ok {
            return false
          }
        }
        true
      })
  }
  !in_boundary
}

///|
/// `RectangleLineIntersector.intersects`.
fn rect_segment_intersects(
  env : Env,
  li : LineIntersector,
  a : Coord,
  b : Coord,
) -> Bool {
  if !env.intersects(Env::of2(a, b)) {
    return false
  }
  if env.intersects_pt(a) || env.intersects_pt(b) {
    return true
  }
  let (p0, p1) = if a.compare(b) > 0 { (b, a) } else { (a, b) }
  if p1.y > p0.y {
    li.compute(p0, p1, { x: env.minx, y: env.maxy, }, {
      x: env.maxx,
      y: env.miny,
    })
  } else {
    li.compute(p0, p1, { x: env.minx, y: env.miny, }, {
      x: env.maxx,
      y: env.maxy,
    })
  }
  li.has_intersection()
}

///|
/// `RectangleIntersects.intersects`: its three visitors in turn over the
/// elements of `g`.
fn rectangle_intersects(rect : Geometry, g : Geometry) -> Bool {
  let env = rect.env()
  if !env.intersects(g.env()) {
    return false
  }
  let elements : Array[(Env, Array[Array[Coord]], Bool)] = []
  for p in g.points {
    elements.push((coords_env([p]), [], false))
  }
  for l in g.lines {
    elements.push((coords_env(l), [l], false))
  }
  for poly in g.polys {
    elements.push((coords_env(poly[0]), poly, true))
  }
  for el in elements {
    let e = el.0
    if !env.intersects(e) {
      continue
    }
    if env.covers(e) ||
      (e.minx >= env.minx && e.maxx <= env.maxx) ||
      (e.miny >= env.miny && e.maxy <= env.maxy) {
      return true
    }
  }
  let corners = rect.polys[0][0]
  for el in elements {
    let (e, rings, is_poly) = el
    if !is_poly || !env.intersects(e) {
      continue
    }
    for k in 0..<4 {
      if e.covers_pt(corners[k]) &&
        locate_point_in_polygon(corners[k], rings) != EXTERIOR {
        return true
      }
    }
  }
  let li = LineIntersector::new()
  for el in elements {
    let (e, rings, _) = el
    if !env.intersects(e) {
      continue
    }
    for line in rings {
      for k in 1..<line.length() {
        if rect_segment_intersects(env, li, line[k - 1], line[k]) {
          return true
        }
      }
    }
  }
  false
}
