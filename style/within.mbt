// Port of `within` of @maplibre/maplibre-gl-style-spec 26.5.0 (within.ts, geometry_util.ts).
// Copyright (c) 2020, MapLibre contributors. BSD 3-Clause License (NOTICE).

///|
/// Tile units per edge of the geometry `within` and `distance` read (MapLibre's
/// `EXTENT`, which `loadGeometry` scales features to).
pub const GEOMETRY_EXTENT : Int32 = 8192

///|
/// A feature's geometry as MapLibre's `loadGeometry` gives it, for `within` and
/// `distance`: `coords` x, y pairs in `GEOMETRY_EXTENT` units, `ring_ends` where
/// each ring (line, point) ends, and its canonical tile `z`, `x`, `y`.
pub(all) struct TileGeometry {
  mut z : Int32
  mut x : Int32
  mut y : Int32
  coords : Array[Int32]
  ring_ends : Array[Int32]
}

///|
pub fn TileGeometry::new() -> TileGeometry {
  { z: 0, x: 0, y: 0, coords: [], ring_ends: [], }
}

///|
/// The rings of `g` as point lists, each point shifted by `shift`.
fn TileGeometry::rings(
  self : TileGeometry,
  shift : (Double, Double),
) -> Array[Array[(Double, Double)]] {
  let out = []
  let mut p = 0
  for end in self.ring_ends {
    let ring = []
    while p < end && p * 2 + 1 < self.coords.length() {
      ring.push(
        (
          self.coords[p * 2].to_double() + shift.0,
          self.coords[p * 2 + 1].to_double() + shift.1,
        ),
      )
      p += 1
    }
    out.push(ring)
  }
  out
}

///|
let pi : Double = 3.141592653589793

///|
/// `2^z` tiles per edge at zoom `z`.
fn tiles_at(z : Int32) -> Double {
  let mut t = 1.0
  for _ in 0..<z {
    t *= 2.0
  }
  t
}

///|
/// MapLibre's `getTileCoordinates`: longitude and latitude in world tile units.
fn tile_coordinates(
  lng : Double,
  lat : Double,
  z : Int32,
  trig : @core.Trig,
) -> (Double, Double) {
  let x = (180.0 + lng) / 360.0
  let y = (
      180.0 - 180.0 / pi * (trig.ln)((trig.tan)(pi / 4.0 + lat * pi / 360.0))
    ) /
    360.0
  let tiles = tiles_at(z)
  let extent = GEOMETRY_EXTENT.to_double()
  (js_round(x * tiles * extent), js_round(y * tiles * extent))
}

///|
/// A bounding box: min x, min y, max x, max y.
priv struct BBox {
  mut x0 : Double
  mut y0 : Double
  mut x1 : Double
  mut y1 : Double
}

///|
fn BBox::empty() -> BBox {
  {
    x0: @double.infinity,
    y0: @double.infinity,
    x1: @double.neg_infinity,
    y1: @double.neg_infinity,
  }
}

///|
fn BBox::add(self : BBox, p : (Double, Double)) -> Unit {
  self.x0 = js_min(self.x0, p.0)
  self.y0 = js_min(self.y0, p.1)
  self.x1 = js_max(self.x1, p.0)
  self.y1 = js_max(self.y1, p.1)
}

///|
fn box_within_box(a : BBox, b : BBox) -> Bool {
  !(a.x0 <= b.x0) && !(a.x1 >= b.x1) && !(a.y0 <= b.y0) && !(a.y1 >= b.y1)
}

///|
fn ray_intersect(
  p : (Double, Double),
  p1 : (Double, Double),
  p2 : (Double, Double),
) -> Bool {
  (p1.1 > p.1) != (p2.1 > p.1) &&
  p.0 < (p2.0 - p1.0) * (p.1 - p1.1) / (p2.1 - p1.1) + p1.0
}

///|
fn on_boundary(
  p : (Double, Double),
  p1 : (Double, Double),
  p2 : (Double, Double),
) -> Bool {
  let x1 = p.0 - p1.0
  let y1 = p.1 - p1.1
  let x2 = p.0 - p2.0
  let y2 = p.1 - p2.1
  x1 * y2 - x2 * y1 == 0.0 && x1 * x2 <= 0.0 && y1 * y2 <= 0.0
}

///|
/// Whether `p1`, `p2` lie on different sides of the line through `q1`, `q2`.
fn two_sided(
  p1 : (Double, Double),
  p2 : (Double, Double),
  q1 : (Double, Double),
  q2 : (Double, Double),
) -> Bool {
  let x1 = p1.0 - q1.0
  let y1 = p1.1 - q1.1
  let x2 = p2.0 - q1.0
  let y2 = p2.1 - q1.1
  let x3 = q2.0 - q1.0
  let y3 = q2.1 - q1.1
  let det1 = x1 * y3 - x3 * y1
  let det2 = x2 * y3 - x3 * y2
  (det1 > 0.0 && det2 < 0.0) || (det1 < 0.0 && det2 > 0.0)
}

///|
/// MapLibre's `segmentIntersectSegment`: false for parallel segments.
fn segments_cross(
  a : (Double, Double),
  b : (Double, Double),
  c : (Double, Double),
  d : (Double, Double),
) -> Bool {
  let (px, py) = (b.0 - a.0, b.1 - a.1)
  let (qx, qy) = (d.0 - c.0, d.1 - c.1)
  if qx * py - qy * px == 0.0 {
    return false
  }
  two_sided(a, b, c, d) && two_sided(c, d, a, b)
}

///|
/// MapLibre's `pointWithinPolygon` (ray casting over every ring).
fn point_within_polygon(
  p : (Double, Double),
  rings : Array[Array[(Double, Double)]],
  on_edge~ : Bool = false,
) -> Bool {
  let mut inside = false
  for ring in rings {
    for j in 0..<(ring.length() - 1) {
      if on_boundary(p, ring[j], ring[j + 1]) {
        return on_edge
      }
      if ray_intersect(p, ring[j], ring[j + 1]) {
        inside = !inside
      }
    }
  }
  inside
}

///|
fn line_within_polygon(
  line : Array[(Double, Double)],
  polygon : Array[Array[(Double, Double)]],
) -> Bool {
  for p in line {
    if !point_within_polygon(p, polygon) {
      return false
    }
  }
  for i in 0..<(line.length() - 1) {
    for ring in polygon {
      for j in 0..<(ring.length() - 1) {
        if segments_cross(line[i], line[i + 1], ring[j], ring[j + 1]) {
          return false
        }
      }
    }
  }
  true
}

///|
/// MapLibre's `updatePoint`: moves `p` by a world to the side of the polygons' box.
fn shift_point(
  p : (Double, Double),
  bbox : BBox,
  poly : BBox,
  world : Double,
) -> (Double, Double) {
  let mut x = p.0
  if x < poly.x0 || x > poly.x1 {
    let half = world * 0.5
    let mut shift = if x - poly.x0 > half {
      -world
    } else if poly.x0 - x > half {
      world
    } else {
      0.0
    }
    if shift == 0.0 {
      shift = if x - poly.x1 > half {
        -world
      } else if poly.x1 - x > half {
        world
      } else {
        0.0
      }
    }
    x += shift
  }
  bbox.add((x, p.1))
  (x, p.1)
}

///|
/// Whether every point or line of `g` (MapLibre's `within` for `kind` "Point"
/// or "LineString"; false for other kinds) lies inside one of `polygons`
/// (longitude, latitude pairs per ring).
pub fn geometry_within(
  polygons : Array[Array[Array[Double]]],
  kind : String,
  g : TileGeometry,
  trig : @core.Trig,
) -> Bool {
  guard kind is ("Point" | "LineString") else { return false }
  let poly_box = BBox::empty()
  let tile_polygons = polygons.map(rings => {
    rings.map(ring => {
      Array::makei(ring.length() / 2, i => {
        let p = tile_coordinates(ring[i * 2], ring[i * 2 + 1], g.z, trig)
        poly_box.add(p)
        p
      })
    })
  })
  let extent = GEOMETRY_EXTENT.to_double()
  let world = tiles_at(g.z) * extent
  let rings = g.rings((g.x.to_double() * extent, g.y.to_double() * extent))
  let bbox = BBox::empty()
  if kind == "Point" {
    let points = []
    for ring in rings {
      for p in ring {
        points.push(shift_point(p, bbox, poly_box, world))
      }
    }
    if !box_within_box(bbox, poly_box) {
      return false
    }
    points
    .iter()
    .all(p => tile_polygons.iter().any(poly => point_within_polygon(p, poly)))
  } else {
    for ring in rings {
      for p in ring {
        bbox.add(p)
      }
    }
    let lines = if bbox.x1 - bbox.x0 <= world / 2.0 {
      let shifted = BBox::empty()
      let lines = rings.map(ring => {
        ring.map(p => shift_point(p, shifted, poly_box, world))
      })
      bbox.x0 = shifted.x0
      bbox.y0 = shifted.y0
      bbox.x1 = shifted.x1
      bbox.y1 = shifted.y1
      lines
    } else {
      rings
    }
    if !box_within_box(bbox, poly_box) {
      return false
    }
    lines
    .iter()
    .all(line => {
      tile_polygons.iter().any(poly => line_within_polygon(line, poly))
    })
  }
}
