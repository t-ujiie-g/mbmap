///|
/// `RayCrossingCounter.locatePointInRing`.
fn locate_in_ring(p : Coord, ring : Array[Coord]) -> Int32 {
  let mut crossings = 0
  for i in 1..<ring.length() {
    let p1 = ring[i]
    let p2 = ring[i - 1]
    if p1.x < p.x && p2.x < p.x {
      continue
    }
    if p.x == p2.x && p.y == p2.y {
      return BOUNDARY
    }
    if p1.y == p.y && p2.y == p.y {
      let mut minx = p1.x
      let mut maxx = p2.x
      if minx > maxx {
        minx = p2.x
        maxx = p1.x
      }
      if p.x >= minx && p.x <= maxx {
        return BOUNDARY
      }
      continue
    }
    if (p1.y > p.y && p2.y <= p.y) || (p2.y > p.y && p1.y <= p.y) {
      let mut orient = orientation_index(p1, p2, p)
      if orient == 0 {
        return BOUNDARY
      }
      if p2.y < p1.y {
        orient = -orient
      }
      if orient == 1 {
        crossings += 1
      }
    }
  }
  if crossings % 2 == 1 {
    INTERIOR
  } else {
    EXTERIOR
  }
}

///|
/// `PointLocator.locateInPolygonRing` and `SimplePointInAreaLocator.locatePointInRing`.
fn locate_in_ring_env(p : Coord, ring : Array[Coord]) -> Int32 {
  if !coords_env(ring).intersects_pt(p) {
    return EXTERIOR
  }
  locate_in_ring(p, ring)
}

///|
/// `PointLocation.isOnLine`.
fn is_on_line(p : Coord, line : Array[Coord]) -> Bool {
  for i in 1..<line.length() {
    if point_on_segment(p, line[i - 1], line[i]) {
      return true
    }
  }
  false
}

///|
fn locate_on_line(p : Coord, line : Array[Coord]) -> Int32 {
  if !coords_env(line).intersects_pt(p) {
    return EXTERIOR
  }
  if !line_closed(line) && (p.eq2d(line[0]) || p.eq2d(line[line.length() - 1])) {
    return BOUNDARY
  }
  if is_on_line(p, line) {
    INTERIOR
  } else {
    EXTERIOR
  }
}

///|
/// `PointLocator.locateInPolygon`.
fn locate_in_polygon(p : Coord, rings : Array[Array[Coord]]) -> Int32 {
  let shell = locate_in_ring_env(p, rings[0])
  if shell == EXTERIOR {
    return EXTERIOR
  }
  if shell == BOUNDARY {
    return BOUNDARY
  }
  for h in 1..<rings.length() {
    let loc = locate_in_ring_env(p, rings[h])
    if loc == INTERIOR {
      return EXTERIOR
    }
    if loc == BOUNDARY {
      return BOUNDARY
    }
  }
  INTERIOR
}

///|
/// `PointLocator.locate` with the mod-2 boundary rule.
fn locate(p : Coord, g : Geometry) -> Int32 {
  match g.kind {
    Empty => return EXTERIOR
    Line => return locate_on_line(p, g.lines[0])
    Poly => return locate_in_polygon(p, g.polys[0])
    _ => ()
  }
  let mut is_in = false
  let mut boundaries = 0
  let update = fn(loc : Int32) {
    if loc == INTERIOR {
      is_in = true
    }
    if loc == BOUNDARY {
      boundaries += 1
    }
  }
  for q in g.points {
    update(if q.eq2d(p) { INTERIOR } else { EXTERIOR })
  }
  for l in g.lines {
    update(locate_on_line(p, l))
  }
  for poly in g.polys {
    update(locate_in_polygon(p, poly))
  }
  if boundaries % 2 == 1 {
    BOUNDARY
  } else if boundaries > 0 || is_in {
    INTERIOR
  } else {
    EXTERIOR
  }
}

///|
/// `SimplePointInAreaLocator.locatePointInPolygon`.
fn locate_point_in_polygon(p : Coord, rings : Array[Array[Coord]]) -> Int32 {
  let shell = locate_in_ring_env(p, rings[0])
  if shell != INTERIOR {
    return shell
  }
  for h in 1..<rings.length() {
    let loc = locate_in_ring_env(p, rings[h])
    if loc == BOUNDARY {
      return BOUNDARY
    }
    if loc == INTERIOR {
      return EXTERIOR
    }
  }
  INTERIOR
}

///|
/// `SimplePointInAreaLocator.locate`: only polygons have an inside.
fn locate_in_area(p : Coord, g : Geometry) -> Int32 {
  if g.kind == Empty || !g.env().intersects_pt(p) {
    return EXTERIOR
  }
  match g.kind {
    Poly => locate_point_in_polygon(p, g.polys[0])
    MultiPoly => {
      for poly in g.polys {
        let loc = locate_point_in_polygon(p, poly)
        if loc != EXTERIOR {
          return loc
        }
      }
      EXTERIOR
    }
    _ => EXTERIOR
  }
}
