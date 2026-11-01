///|
/// Degrees to Clipper's integers: 1e-7 degree (about 1 cm) steps.
pub const DEGREE_SCALE : Double = 10000000.0

///|
/// Meters to Clipper's integers in the planes buffers are made in: 1 mm steps.
const METER_SCALE : Double = 1000.0

///|
/// A feature's geometry as Clipper paths: rings of polygons, lines, or points
/// (each a path of one point), in `to_int`'s integers.
priv struct Shape {
  polygons : Array[Array[@clipper.Point64]]
  lines : Array[Array[@clipper.Point64]]
  points : Array[@clipper.Point64]
}

///|
/// Feature `f` of `t` with each coordinate mapped by `to_int`, edges longer than
/// `densify` degrees (if positive) split evenly.
fn shape_of(
  t : @geom.Table,
  f : Int32,
  to_int : (Double, Double) -> @clipper.Point64,
  densify~ : Double = 0.0,
) -> Shape {
  let shape = { polygons: [], lines: [], points: [], }
  let (p0, p1) = t.parts(f)
  for p in p0..<p1 {
    let (r0, r1) = t.rings(p)
    for r in r0..<r1 {
      let (i0, i1) = t.points(r)
      let path = []
      for i in i0..<i1 {
        let x = t.coords[i * 2]
        let y = t.coords[i * 2 + 1]
        // Edges are straight in longitude and latitude (RFC 7946); split long
        // ones so they stay so in the plane they are projected to.
        if densify > 0.0 && i > i0 {
          let px = t.coords[i * 2 - 2]
          let py = t.coords[i * 2 - 1]
          let len = ((x - px) * (x - px) + (y - py) * (y - py)).sqrt()
          let n = (len / densify).ceil().to_int()
          for k in 1..<n {
            let w = k.to_double() / n.to_double()
            path.push(to_int(px + (x - px) * w, py + (y - py) * w))
          }
        }
        path.push(to_int(x, y))
      }
      match t.kinds[f] {
        Polygon | MultiPolygon => shape.polygons.push(path)
        LineString | MultiLineString => shape.lines.push(path)
        Point | MultiPoint =>
          for pt in path {
            shape.points.push(pt)
          }
        NoGeometry => ()
      }
    }
  }
  shape
}

///|
/// `rings` with holes and outers wound consistently (outers counter-clockwise
/// in a y-up frame), whatever their input orientation: their even-odd union.
fn normalized(
  rings : Array[Array[@clipper.Point64]],
) -> Array[Array[@clipper.Point64]] {
  if rings.is_empty() {
    return []
  }
  @clipper.union(rings, [], EvenOdd)
}

///|
/// Appends a ring, repeating its first point as GeoJSON does.
fn add_ring(
  b : @geom.TableBuilder,
  path : Array[@clipper.Point64],
  to_xy : (@clipper.Point64) -> (Double, Double),
) -> Unit {
  for pt in path {
    let (x, y) = to_xy(pt)
    b.point(x, y)
  }
  if path.length() > 0 {
    let (x, y) = to_xy(path[0])
    b.point(x, y)
  }
  b.end_ring()
}

///|
/// Appends a solution tree's polygons to `b` as parts (an outer ring, then its
/// holes; islands in holes are parts of their own), with each point mapped
/// back by `to_xy`. Returns how many parts it added.
fn add_tree(
  b : @geom.TableBuilder,
  root : @clipper.PolyPath64,
  to_xy : (@clipper.Point64) -> (Double, Double),
) -> Int32 {
  let mut parts = 0
  let stack = [root.children]
  while stack.pop() is Some(outers) {
    for outer in outers {
      add_ring(b, outer.polygon, to_xy)
      for hole in outer.children {
        add_ring(b, hole.polygon, to_xy)
        if hole.children.length() > 0 {
          stack.push(hole.children)
        }
      }
      b.end_part()
      parts += 1
    }
  }
  parts
}
