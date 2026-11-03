///|
/// How far (in 1e-7 degree steps) a cut's end may lie from a ring's edge and
/// still count as on it: Clipper rounds crossings to its integer grid.
const ON_EDGE : Double = 2.0

///|
/// A part of a polygon feature: its outer ring and holes, unclosed.
priv struct Part {
  outer : Array[@clipper.Point64]
  holes : Array[Array[@clipper.Point64]]
}

///|
/// The parts of polygon feature `f`, in Clipper's integers.
fn parts_of(t : @geom.Table, f : Int32) -> Array[Part] {
  let out = []
  let (p0, p1) = t.parts(f)
  for p in p0..<p1 {
    let (r0, r1) = t.rings(p)
    let rings = []
    for r in r0..<r1 {
      let (i0, i1) = t.points(r)
      let ring = deduped(
        Array::makei(i1 - i0, i => {
          degree_int(t.coords[(i0 + i) * 2], t.coords[(i0 + i) * 2 + 1])
        }),
      )
      if ring.length() >= 3 {
        rings.push(ring)
      }
    }
    if rings.length() > 0 {
      out.push({ outer: rings[0], holes: rings[1:].to_owned(), })
    }
  }
  out
}

///|
/// Distance from `p` to segment `a`-`b`, and how far along it the nearest
/// point lies (0 to 1).
fn to_segment(
  p : @clipper.Point64,
  a : @clipper.Point64,
  b : @clipper.Point64,
) -> (Double, Double) {
  let (px, py) = (p.x.to_double(), p.y.to_double())
  let (ax, ay) = (a.x.to_double(), a.y.to_double())
  let dx = b.x.to_double() - ax
  let dy = b.y.to_double() - ay
  let len = dx * dx + dy * dy
  let t = if len == 0.0 {
    0.0
  } else {
    @cmp.maximum(
      0.0,
      @cmp.minimum(1.0, ((px - ax) * dx + (py - ay) * dy) / len),
    )
  }
  let ex = ax + t * dx - px
  let ey = ay + t * dy - py
  ((ex * ex + ey * ey).sqrt(), t)
}

///|
/// The edge of `ring` (from point i to i + 1) that `p` lies on, and how far
/// along it; None if `p` is off the ring.
fn edge_of(
  ring : Array[@clipper.Point64],
  p : @clipper.Point64,
) -> (Int32, Double)? {
  let n = ring.length()
  let mut best : (Int32, Double)? = None
  let mut dist = ON_EDGE
  for i in 0..<n {
    let (d, t) = to_segment(p, ring[i], ring[(i + 1) % n])
    if d <= dist {
      dist = d
      best = Some((i, t))
    }
  }
  best
}

///|
/// `path` without points equal to the one before (and to the first, at the end).
fn deduped(path : Array[@clipper.Point64]) -> Array[@clipper.Point64] {
  let out = []
  for p in path {
    if out.last() != Some(p) {
      out.push(p)
    }
  }
  while out.length() > 1 && out[0] == out[out.length() - 1] {
    out.pop() |> ignore
  }
  out
}

///|
/// `ring` cut along `chord`, whose ends lie on edges `i` (at `ti`) and `j`
/// (at `tj`): the two rings on either side, walking the ring forward from
/// each end to the other and back along the chord.
fn cut_ring(
  ring : Array[@clipper.Point64],
  chord : Array[@clipper.Point64],
  i : Int32,
  ti : Double,
  j : Int32,
  tj : Double,
) -> (Array[@clipper.Point64], Array[@clipper.Point64]) {
  let (chord, i, j) = if i > j || (i == j && ti > tj) {
    (chord.rev(), j, i)
  } else {
    (chord, i, j)
  }
  let n = ring.length()
  let e0 = chord[0]
  let e1 = chord[chord.length() - 1]
  let inner = chord[1:chord.length() - 1].to_owned()
  let a = [e0]
  for k in (i + 1)..<=j {
    a.push(ring[k % n])
  }
  a.push(e1)
  for k = inner.length() - 1; k >= 0; k = k - 1 {
    a.push(inner[k])
  }
  let b = [e1]
  for k in (j + 1)..<=(i + n) {
    b.push(ring[k % n])
  }
  b.push(e0)
  for p in inner {
    b.push(p)
  }
  (deduped(a), deduped(b))
}

///|
/// The pieces `lines` cut a polygon part into: each stretch of a line that
/// crosses a piece from edge to edge divides it (holes go to the piece around
/// them; stretches ending inside, or meeting a hole, cut nothing).
fn split_part(
  part : Part,
  lines : Array[Array[@clipper.Point64]],
) -> Array[Part] {
  let pieces = [part.outer]
  for line in lines {
    let c = @clipper.Clipper64::new()
    c.add_open_subject([line])
    c.add_clip([part.outer, ..part.holes])
    guard c.execute(Intersection, NonZero) is Some((_, chords)) else {
      continue
    }
    for raw in chords {
      let chord = deduped(raw)
      guard chord.length() >= 2 else { continue }
      // A point just inside the piece the chord crosses.
      let mid : @clipper.Point64 = {
        x: (chord[0].x + chord[1].x) / 2L,
        y: (chord[0].y + chord[1].y) / 2L,
      }
      guard pieces.search_by(r => {
          @clipper.point_in_polygon(mid, r[:]) is IsInside
        })
        is Some(k) else {
        continue
      }
      let ring = pieces[k]
      guard edge_of(ring, chord[0]) is Some((i, ti)) &&
        edge_of(ring, chord[chord.length() - 1]) is Some((j, tj)) else {
        continue
      }
      let (a, b) = cut_ring(ring, chord, i, ti, j, tj)
      guard a.length() >= 3 &&
        b.length() >= 3 &&
        @clipper.area(a[:]) != 0.0 &&
        @clipper.area(b[:]) != 0.0 else {
        continue
      }
      pieces[k] = a
      pieces.push(b)
    }
  }
  pieces.map(outer => {
    outer,
    holes: part.holes.filter(h => {
      @clipper.point_in_polygon(h[0], outer[:]) is IsInside
    }),
  })
}

///|
/// Appends `ring` closed, counter-clockwise (`ccw`) or clockwise.
fn add_oriented(
  b : @geom.TableBuilder,
  ring : Array[@clipper.Point64],
  ccw : Bool,
) -> Unit {
  let ring = if (@clipper.area(ring[:]) > 0.0) == ccw {
    ring
  } else {
    ring.rev()
  }
  add_ring(b, ring, degree_xy)
}

///|
/// Where line `p`-`q` crosses line `r`-`s`: the parameter along `p`-`q`
/// strictly inside it, with `r`-`s` touched anywhere along its length.
fn crossing(
  p : (Double, Double),
  q : (Double, Double),
  r : (Double, Double),
  s : (Double, Double),
) -> Double? {
  let (dx, dy) = (q.0 - p.0, q.1 - p.1)
  let (ex, ey) = (s.0 - r.0, s.1 - r.1)
  let den = dx * ey - dy * ex
  if den == 0.0 {
    return None
  }
  let t = ((r.0 - p.0) * ey - (r.1 - p.1) * ex) / den
  let u = ((r.0 - p.0) * dy - (r.1 - p.1) * dx) / den
  if t > 0.0 && t < 1.0 && u >= 0.0 && u <= 1.0 {
    Some(t)
  } else {
    None
  }
}

///|
/// Line `ring` of feature `f` (in degrees) cut where `cuts` cross it.
fn split_line(
  t : @geom.Table,
  ring : Int32,
  cuts : Array[Array[(Double, Double)]],
) -> Array[Array[(Double, Double)]] {
  let (i0, i1) = t.points(ring)
  let out = [[]]
  for i in i0..<i1 {
    let p = (t.coords[i * 2], t.coords[i * 2 + 1])
    out[out.length() - 1].push(p)
    if i + 1 == i1 {
      break
    }
    let q = (t.coords[i * 2 + 2], t.coords[i * 2 + 3])
    let at = []
    for cut in cuts {
      for k in 1..<cut.length() {
        if crossing(p, q, cut[k - 1], cut[k]) is Some(x) {
          at.push(x)
        }
      }
    }
    at.sort()
    for x in at {
      let c = (p.0 + (q.0 - p.0) * x, p.1 + (q.1 - p.1) * x)
      out[out.length() - 1].push(c)
      out.push([c])
    }
  }
  out
}

///|
/// Each feature of `a` split by the lines of `b` into features with its
/// properties: polygons where a line crosses edge to edge (1e-7 degree grid),
/// lines where they cross; the rest stays whole.
pub fn split(a : @geom.Table, b : @geom.Table) -> @geom.Table {
  let lines = []
  let cuts = []
  for g in 0..<b.length() {
    guard b.kinds[g] is (LineString | MultiLineString) else { continue }
    for l in shape_of(b, g, degree_int).lines {
      lines.push(l)
      cuts.push(l.map(degree_xy))
    }
  }
  let out = @geom.TableBuilder::new()
  for f in 0..<a.length() {
    match a.kinds[f] {
      Polygon | MultiPolygon =>
        for part in parts_of(a, f) {
          for piece in split_part(part, lines) {
            add_oriented(out, piece.outer, true)
            for h in piece.holes {
              add_oriented(out, h, false)
            }
            out.end_part()
            copy_props(out, a, f)
            out.end_feature(Polygon)
          }
        }
      LineString | MultiLineString => {
        let (p0, p1) = a.parts(f)
        for p in p0..<p1 {
          let (r0, _) = a.rings(p)
          for piece in split_line(a, r0, cuts) {
            guard piece.length() >= 2 else { continue }
            for pt in piece {
              out.point(pt.0, pt.1)
            }
            out.end_ring()
            out.end_part()
            copy_props(out, a, f)
            out.end_feature(LineString)
          }
        }
      }
      _ => {
        let (p0, p1) = a.parts(f)
        for p in p0..<p1 {
          let (r0, r1) = a.rings(p)
          for r in r0..<r1 {
            let (i0, i1) = a.points(r)
            for i in i0..<i1 {
              out.point(a.coords[i * 2], a.coords[i * 2 + 1])
            }
            out.end_ring()
          }
          out.end_part()
        }
        copy_props(out, a, f)
        out.end_feature(a.kinds[f])
      }
    }
  }
  out.finish()
}

///|
/// The features of `t` as one, with the first one's properties: polygons
/// united, lines joined where one ends at another's end (a MultiLineString if
/// some do not meet), points as a MultiPoint; None if their kinds differ.
pub fn merge(t : @geom.Table) -> @geom.Table? {
  let family = (k : @geom.GeomKind) => {
    match k {
      Polygon | MultiPolygon => 0
      LineString | MultiLineString => 1
      Point | MultiPoint => 2
      NoGeometry => 3
    }
  }
  guard t.length() > 0 else { return None }
  let kind = family(t.kinds[0])
  guard kind < 3 && t.kinds.iter().all(k => family(k) == kind) else {
    return None
  }
  let out = @geom.TableBuilder::new()
  let result_kind : @geom.GeomKind = match kind {
    0 => {
      let all = []
      for f in 0..<t.length() {
        for ring in normalized(shape_of(t, f, degree_int).polygons) {
          all.push(ring)
        }
      }
      polygon_kind(
        add_tree(out, tree_of(@clipper.union(all, [], NonZero)), degree_xy),
      )
    }
    1 => {
      let paths : Array[Array[(Double, Double)]] = []
      for f in 0..<t.length() {
        let (p0, p1) = t.parts(f)
        for p in p0..<p1 {
          let (r0, _) = t.rings(p)
          let (i0, i1) = t.points(r0)
          paths.push(
            Array::makei(i1 - i0, i => {
              (t.coords[(i0 + i) * 2], t.coords[(i0 + i) * 2 + 1])
            }),
          )
        }
      }
      let joined = join_lines(paths)
      for line in joined {
        for pt in line {
          out.point(pt.0, pt.1)
        }
        out.end_ring()
        out.end_part()
      }
      if joined.length() == 1 {
        LineString
      } else {
        MultiLineString
      }
    }
    _ => {
      for f in 0..<t.length() {
        let (p0, p1) = t.parts(f)
        for p in p0..<p1 {
          let (r0, r1) = t.rings(p)
          for r in r0..<r1 {
            let (i0, i1) = t.points(r)
            for i in i0..<i1 {
              out.point(t.coords[i * 2], t.coords[i * 2 + 1])
            }
          }
        }
      }
      out.end_ring()
      out.end_part()
      MultiPoint
    }
  }
  copy_props(out, t, 0)
  out.end_feature(result_kind)
  Some(out.finish())
}

///|
/// `paths` joined end to end where an end of one equals an end of another,
/// reversing paths as needed; those that meet nothing stay apart.
fn join_lines(
  paths : Array[Array[(Double, Double)]],
) -> Array[Array[(Double, Double)]] {
  let left = paths.copy()
  let out = []
  while left.length() > 0 {
    let line = left.remove(0)
    let mut grown = true
    while grown {
      grown = false
      for k, other in left {
        let (head, tail) = (line[0], line[line.length() - 1])
        let (start, end) = (other[0], other[other.length() - 1])
        let next = if start == tail {
          Some(line + other[1:].to_owned())
        } else if end == tail {
          Some(line + other.rev()[1:].to_owned())
        } else if end == head {
          Some(other + line[1:].to_owned())
        } else if start == head {
          Some(other.rev() + line[1:].to_owned())
        } else {
          None
        }
        if next is Some(joined) {
          line.clear()
          line.append(joined)
          left.remove(k) |> ignore
          grown = true
          break
        }
      }
    }
    out.push(line)
  }
  out
}
