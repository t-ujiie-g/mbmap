// Side faces port `_generateSideFaces` and `addVertex` from MapLibre GL JS
// 6.16.0 (src/data/bucket/fill_extrusion_bucket.ts, src/data/extent_bounds.ts),
// BSD 3-Clause License, Copyright (c) 2020, MapLibre contributors. See NOTICE.

///|
/// Ints per extrusion vertex in `ExtrusionBuffers.vertices`: x, y, normal x
/// (times 2^14, plus 1 on the top edge), normal y and z (times 2^14), the
/// distance along the ring's walls (for patterns, rounded in MapLibre's
/// 8192-unit tile whatever the source's extent; 0 on roofs), and the
/// feature's centroid x, y (where terrain lifts it from).
pub const EXTRUSION_VERTEX_STRIDE : Int32 = 8

///|
/// `ExtrusionBuffers.heights` per vertex: the feature's base at the tile's zoom
/// and one zoom deeper, then its height at both.
pub const EXTRUSION_HEIGHTS : Int32 = 4

///|
/// Extruded polygons: roofs (normal up, top edge) and walls (a quad per ring
/// edge, normal outwards), with each vertex's heights and triangles as index
/// triples.
pub struct ExtrusionBuffers {
  vertices : Array[Int32]
  heights : Array[Double]
  indices : Array[Int32]
}

///|
pub fn ExtrusionBuffers::new() -> ExtrusionBuffers {
  { vertices: [], heights: [], indices: [], }
}

///|
pub fn ExtrusionBuffers::clear(self : ExtrusionBuffers) -> Unit {
  self.vertices.clear()
  self.heights.clear()
  self.indices.clear()
}

///|
pub fn ExtrusionBuffers::num_vertices(self : ExtrusionBuffers) -> Int32 {
  self.vertices.length() / EXTRUSION_VERTEX_STRIDE
}

///|
/// Extrudes polygon features as MapLibre's fill-extrusion bucket does. Reuse
/// one instance: its buffers keep their capacity.
pub struct ExtrusionTessellator {
  priv fill : FillTessellator
  priv roof : FillBuffers
}

///|
pub fn ExtrusionTessellator::new() -> ExtrusionTessellator {
  { fill: FillTessellator::new(), roof: FillBuffers::new(), }
}

///|
/// Normal components are scaled by 2^13 and doubled (MapLibre's `FACTOR`), so
/// the lowest bit of x can say whether the vertex is on the top edge.
const NORMAL_FACTOR : Double = 8192.0

///|
/// MapLibre's tile extent, the unit of wall distances.
const WALL_EXTENT : Double = 8192.0

///|
/// A wall distance in `WALL_EXTENT` units, rounded as MapLibre's `addVertex`
/// and kept within Int16.
fn wall_distance(along : Double, extent : Int32) -> Int32 {
  @cmp.minimum(
    (along * WALL_EXTENT / extent.to_double()).round().to_int(),
    32767,
  )
}

///|
fn ExtrusionBuffers::vertex(
  self : ExtrusionBuffers,
  x : Int32,
  y : Int32,
  normal : (Double, Double, Double),
  top : Int32,
  centroid : (Int32, Int32),
  heights : FixedArray[Double],
  edge~ : Int32 = 0,
) -> Unit {
  let (nx, ny, nz) = normal
  let v = self.vertices
  v.push(x)
  v.push(y)
  v.push((nx * NORMAL_FACTOR).floor().to_int() * 2 + top)
  v.push((ny * NORMAL_FACTOR * 2.0).to_int())
  v.push((nz * NORMAL_FACTOR * 2.0).to_int())
  v.push(edge)
  v.push(centroid.0)
  v.push(centroid.1)
  for h in heights {
    self.heights.push(h)
  }
}

///|
/// Whether the edge runs along a line the tile was cut at, outside `[0,
/// extent]`: the neighboring tile owns the wall there (MapLibre's
/// `isBoundaryEdge`).
fn boundary_edge(
  x1 : Int32,
  y1 : Int32,
  x2 : Int32,
  y2 : Int32,
  extent : Int32,
) -> Bool {
  (x1 == x2 && (x1 < 0 || x1 > extent)) || (y1 == y2 && (y1 < 0 || y1 > extent))
}

///|
/// Whether every point of `[start, end)` lies beyond the same edge of the tile.
fn entirely_outside(
  coords : ArrayView[Int32],
  start : Int32,
  end : Int32,
  extent : Int32,
) -> Bool {
  let mut left = true
  let mut right = true
  let mut top = true
  let mut bottom = true
  for i in start..<end {
    let x = coords[i * 2]
    let y = coords[i * 2 + 1]
    left = left && x < 0
    right = right && x > extent
    top = top && y < 0
    bottom = bottom && y > extent
  }
  left || right || top || bottom
}

///|
/// Appends one polygon feature's rings extruded: walls along rings reaching the
/// tile, roofs triangulated like fills; `heights` are its `EXTRUSION_HEIGHTS`.
/// The centroid is the whole feature's (MapLibre takes each polygon's).
pub fn ExtrusionTessellator::add_polygons(
  self : ExtrusionTessellator,
  coords : ArrayView[Int32],
  ring_ends : ArrayView[Int32],
  heights : FixedArray[Double],
  out : ExtrusionBuffers,
  extent~ : Int32 = 4096,
) -> Unit {
  let points = if ring_ends.length() == 0 {
    0
  } else {
    ring_ends[ring_ends.length() - 1]
  }
  if points == 0 {
    return
  }
  // The mean of the ring points, without a ring's closing repeat of its first.
  let mut sx = 0.0
  let mut sy = 0.0
  let mut count = 0
  for r in 0..<ring_ends.length() {
    let start = if r == 0 { 0 } else { ring_ends[r - 1] }
    let end = ring_ends[r]
    for i in start..<end {
      if i == end - 1 &&
        end - start > 1 &&
        coords[i * 2] == coords[start * 2] &&
        coords[i * 2 + 1] == coords[start * 2 + 1] {
        continue
      }
      sx += coords[i * 2].to_double()
      sy += coords[i * 2 + 1].to_double()
      count += 1
    }
  }
  let centroid = (
    (sx / count.to_double()).floor().to_int(),
    (sy / count.to_double()).floor().to_int(),
  )
  for r in 0..<ring_ends.length() {
    let start = if r == 0 { 0 } else { ring_ends[r - 1] }
    let end = ring_ends[r]
    if end - start < 2 || entirely_outside(coords, start, end, extent) {
      continue
    }
    // Edges from each point back to the one before it, the closing one last;
    // MapLibre starts the distance again past 32768 of its 8192-unit tile.
    let mut along = 0.0
    let restart = 4.0 * extent.to_double()
    for k in (start + 1)..<=end {
      let i = if k == end { start } else { k }
      let j = k - 1
      let x1 = coords[i * 2]
      let y1 = coords[i * 2 + 1]
      let x2 = coords[j * 2]
      let y2 = coords[j * 2 + 1]
      if boundary_edge(x1, y1, x2, y2, extent) {
        continue
      }
      let dx = x1.to_double() - x2.to_double()
      let dy = y1.to_double() - y2.to_double()
      let len = (dx * dx + dy * dy).sqrt()
      if len == 0.0 {
        continue
      }
      let normal = (-dy / len, dx / len, 0.0)
      if along + len > restart {
        along = 0.0
      }
      let b = out.num_vertices()
      let e1 = wall_distance(along, extent)
      out.vertex(x1, y1, normal, 0, centroid, heights, edge=e1)
      out.vertex(x1, y1, normal, 1, centroid, heights, edge=e1)
      along += len
      let e2 = wall_distance(along, extent)
      out.vertex(x2, y2, normal, 0, centroid, heights, edge=e2)
      out.vertex(x2, y2, normal, 1, centroid, heights, edge=e2)
      for k in [0, 2, 1, 1, 2, 3] {
        out.indices.push(b + k)
      }
    }
  }
  let roof = self.roof
  roof.clear()
  self.fill.add_polygons(coords, ring_ends, roof)
  let b = out.num_vertices()
  for i in 0..<roof.num_vertices() {
    out.vertex(
      roof.vertices[i * 2],
      roof.vertices[i * 2 + 1],
      (0.0, 0.0, 1.0),
      1,
      centroid,
      heights,
    )
  }
  for t in roof.indices {
    out.indices.push(b + t)
  }
}
