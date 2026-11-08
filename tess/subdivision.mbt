// A port of MapLibre GL JS 6.16.0's src/render/subdivision.ts, with the granularity of
// src/render/subdivision_granularity_settings.ts and the globe's settings of
// src/geo/projection/vertical_perspective_projection.ts. BSD-3-Clause, Copyright (c) 2020
// MapLibre contributors; see NOTICE.

///|
/// Cells per tile edge at zoom `z` of a setting that cuts zoom 0 into `base`,
/// halving per zoom down to `min` and 1 (`getGranularityForZoomLevel`, JS shift included).
pub fn granularity_for_zoom(base : Int32, min : Int32, z : Int32) -> Int32 {
  let divisor = 1 << (z & 31)
  let g = (base.to_double() / divisor.to_double()).floor().to_int()
  @cmp.maximum(@cmp.maximum(g, min), 1)
}

///|
/// The globe's granularity for fills and extrusions (`fill: (128, 2)`).
pub fn fill_granularity(z : Int32) -> Int32 {
  granularity_for_zoom(128, 2, z)
}

///|
/// The globe's granularity for lines (`line: (512, 0)`).
pub fn line_granularity(z : Int32) -> Int32 {
  granularity_for_zoom(512, 0, z)
}

///|
/// The globe's granularity of map-aligned circles and heatmap kernels (`circle: 3`).
pub const CIRCLE_GRANULARITY : Int32 = 3

///|
/// Open-addressing map from a vertex key to its index; `reset` empties it by
/// moving to the next generation, so reuse does not clear the slots.
priv struct VertexMap {
  mut keys : FixedArray[Int32]
  mut values : FixedArray[Int32]
  mut stamps : FixedArray[Int32]
  mut gen : Int32
  mut count : Int32
  mut bits : Int32
}

///|
fn VertexMap::new() -> VertexMap {
  let bits = 10
  {
    keys: FixedArray::make(1 << bits, 0),
    values: FixedArray::make(1 << bits, 0),
    stamps: FixedArray::make(1 << bits, 0),
    gen: 1,
    count: 0,
    bits,
  }
}

///|
fn VertexMap::reset(self : VertexMap) -> Unit {
  self.count = 0
  if self.gen == 0x7fffffff {
    self.stamps.fill(0)
    self.gen = 0
  }
  self.gen += 1
}

///|
fn VertexMap::slot(self : VertexMap, key : Int32) -> Int32 {
  let mask = (1 << self.bits) - 1
  let mut s = ((key * -1640531535) >> (32 - self.bits)) & mask
  while self.stamps[s] == self.gen && self.keys[s] != key {
    s = (s + 1) & mask
  }
  s
}

///|
fn VertexMap::grow(self : VertexMap) -> Unit {
  let keys = self.keys
  let values = self.values
  let stamps = self.stamps
  let gen = self.gen
  self.bits += 1
  let size = 1 << self.bits
  self.keys = FixedArray::make(size, 0)
  self.values = FixedArray::make(size, 0)
  self.stamps = FixedArray::make(size, 0)
  self.gen = 1
  for i in 0..<keys.length() {
    if stamps[i] == gen {
      let s = self.slot(keys[i])
      self.keys[s] = keys[i]
      self.values[s] = values[i]
      self.stamps[s] = 1
    }
  }
}

///|
/// The value stored for `key`, or `value` once stored for it.
fn VertexMap::get_or_insert(
  self : VertexMap,
  key : Int32,
  value : Int32,
) -> Int32 {
  let s = self.slot(key)
  if self.stamps[s] == self.gen {
    return self.values[s]
  }
  if (self.count + 1) * 2 > 1 << self.bits {
    self.grow()
    return self.get_or_insert(key, value)
  }
  self.keys[s] = key
  self.values[s] = value
  self.stamps[s] = self.gen
  self.count += 1
  value
}

///|
/// Subdivides polygons for the globe (MapLibre's `subdividePolygon`). After
/// `subdivide_polygon`, `vertices` holds x, y pairs, `triangles` vertex index
/// triples (counter-clockwise), and `lines` each ring's outline as index pairs,
/// ring `r` ending at `line_ends[r]`. Reuse one instance across polygons.
pub struct Subdivider {
  vertices : Array[Int32]
  triangles : Array[Int32]
  lines : Array[Int32]
  line_ends : Array[Int32]
  priv map : VertexMap
  priv earcut : Earcut
  priv holes : Array[Int32]
  priv remap : Array[Int32]
  priv earcut_out : Array[Int32]
  priv ring : Array[Int32]
  priv points : Array[Int32]
  priv path : Array[Int32]
  priv tri_xy : FixedArray[Double]
  priv tri_ids : FixedArray[Int32]
  priv mut granularity : Int32
  priv mut cell : Double
  priv mut failed : Bool
}

///|
pub fn Subdivider::new() -> Subdivider {
  {
    vertices: [],
    triangles: [],
    lines: [],
    line_ends: [],
    map: VertexMap::new(),
    earcut: Earcut::new(),
    holes: [],
    remap: [],
    earcut_out: [],
    ring: [],
    points: [],
    path: [],
    tri_xy: FixedArray::make(6, 0.0),
    tri_ids: FixedArray::make(3, 0),
    granularity: 0,
    cell: 0.0,
    failed: false,
  }
}

///|
/// `Math.round(x) | 0` for `x` within Int16.
fn round_int(x : Double) -> Int32 {
  if x.is_nan() {
    0
  } else {
    @core.js_round(x).to_int()
  }
}

///|
/// The index of the vertex at `x`, `y` rounded, added if new (`_vertexToIndex`).
/// Coordinates out of Int16 make MapLibre throw; here they set `failed`.
fn Subdivider::vertex_to_index(
  self : Subdivider,
  x : Double,
  y : Double,
) -> Int32 {
  if self.failed {
    return 0
  }
  if x < -32768.0 || y < -32768.0 || x > 32767.0 || y > 32767.0 {
    self.failed = true
    return 0
  }
  let xi = round_int(x)
  let yi = round_int(y)
  let key = ((xi + 32768) << 16) | (yi + 32768)
  let index = self.vertices.length() / 2
  let found = self.map.get_or_insert(key, index)
  if found == index {
    self.vertices.push(xi)
    self.vertices.push(yi)
  }
  found
}

///|
/// Subdivides one polygon: `coords` holds its rings' x, y pairs (outer ring
/// first, then holes), ring `r` ending at vertex `ring_ends[r]`; `granularity`
/// below 2 does not subdivide. `canonical` adds the pole caps of a tile in the
/// first or last row and, at zoom 0, drops geometry beyond the tile's x range.
///
/// Returns false where MapLibre throws: a vertex out of Int16. If only the
/// triangles' subdivision fails (MapLibre logs it and leaves them undefined),
/// `triangles` stays empty, unless poles or zoom 0 need them, which fails.
pub fn Subdivider::subdivide_polygon(
  self : Subdivider,
  coords : ArrayView[Int32],
  ring_ends : ArrayView[Int32],
  granularity : Int32,
  canonical? : @core.TileId,
  outline~ : Bool = true,
) -> Bool {
  self.vertices.clear()
  self.triangles.clear()
  self.lines.clear()
  self.line_ends.clear()
  self.map.reset()
  self.failed = false
  self.granularity = granularity
  self.cell = @core.TILE_EXTENT.to_double() / granularity.to_double()
  let n = ring_ends.length()
  let total = if n > 0 { ring_ends[n - 1] } else { 0 }
  self.holes.clear()
  for r in 1..<n {
    if ring_ends[r] > ring_ends[r - 1] {
      self.holes.push(ring_ends[r - 1])
    }
  }
  self.remap.clear()
  for i in 0..<total {
    self.remap.push(
      self.vertex_to_index(
        coords[i * 2].to_double(),
        coords[i * 2 + 1].to_double(),
      ),
    )
  }
  if self.failed {
    return false
  }
  self.earcut_out.clear()
  self.earcut.triangulate(coords[0:total * 2], self.holes[:], self.earcut_out)
  self.subdivide_triangles()
  let triangles_failed = self.failed
  if triangles_failed {
    self.triangles.clear()
    self.failed = false
  }
  if outline {
    self.generate_outline(coords, ring_ends)
    if self.failed {
      return false
    }
  }
  self.ensure_no_pole_vertices()
  if canonical is Some(c) {
    let north = c.y == 0
    let south = c.y == (1 << c.z) - 1
    if north || south {
      if triangles_failed {
        return false
      }
      self.fill_poles(north, south)
    }
    if granularity >= 2 && c.z == 0 {
      if triangles_failed {
        return false
      }
      remove_outside_tile_x(
        self.vertices,
        self.triangles,
        0,
        self.triangles.length(),
        3,
      )
      |> ignore
      let mut start = 0
      let mut removed = 0
      for r in 0..<self.line_ends.length() {
        let old_end = self.line_ends[r] - removed
        let end = remove_outside_tile_x(
          self.vertices,
          self.lines,
          start,
          old_end,
          2,
        )
        removed += old_end - end
        self.line_ends[r] = end
        start = end
      }
    }
  }
  true
}

///|
/// `_subdivideTrianglesScanline` over `earcut_out`, into `triangles`.
fn Subdivider::subdivide_triangles(self : Subdivider) -> Unit {
  let input = self.earcut_out
  let remap = self.remap
  let out = self.triangles
  if self.granularity < 2 {
    fix_winding_order(self.vertices, input, remap, out)
    return
  }
  let v = self.vertices
  let xy = self.tri_xy
  let ids = self.tri_ids
  let cell = self.cell
  for p = 0; p < input.length(); p = p + 3 {
    for k in 0..<3 {
      let i = remap[input[p + k]]
      ids[k] = i
      xy[k * 2] = v[i * 2].to_double()
      xy[k * 2 + 1] = v[i * 2 + 1].to_double()
    }
    let min_x = @cmp.minimum(@cmp.minimum(xy[0], xy[2]), xy[4])
    let max_x = @cmp.maximum(@cmp.maximum(xy[0], xy[2]), xy[4])
    let min_y = @cmp.minimum(@cmp.minimum(xy[1], xy[3]), xy[5])
    let max_y = @cmp.maximum(@cmp.maximum(xy[1], xy[3]), xy[5])
    if min_x == max_x || min_y == max_y {
      continue
    }
    let cell_x_min = (min_x / cell).floor()
    let cell_x_max = (max_x / cell).ceil()
    let cell_y_min = (min_y / cell).floor()
    let cell_y_max = (max_y / cell).ceil()
    if cell_x_min == cell_x_max && cell_y_min == cell_y_max {
      out.push(ids[0])
      out.push(ids[1])
      out.push(ids[2])
      continue
    }
    for row = cell_y_min; row < cell_y_max; row = row + 1.0 {
      self.ring.clear()
      self.ring_for_row(row)
      if self.failed {
        return
      }
      if !scanline_triangulate_ring(v, self.ring, out) {
        self.failed = true
        return
      }
    }
  }
}

///|
/// The ring of the triangle in `tri_xy` / `tri_ids` cut to cell row `row`
/// (`_scanlineGenerateVertexRingForCellRow`), into `ring`.
fn Subdivider::ring_for_row(self : Subdivider, row : Double) -> Unit {
  let top = row * self.cell
  let bottom = top + self.cell
  let xy = self.tri_xy
  let ring = self.ring
  for e in 0..<3 {
    let ax = xy[e * 2]
    let ay = xy[e * 2 + 1]
    let bx = xy[(e + 1) * 2 % 6]
    let by = xy[((e + 1) * 2 + 1) % 6]
    let cx = xy[(e + 2) * 2 % 6]
    let cy = xy[((e + 2) * 2 + 1) % 6]
    let dir_x = bx - ax
    let dir_y = by - ay
    let parallel_y = dir_x == 0.0
    let parallel_x = dir_y == 0.0
    let t_top = (top - ay) / dir_y
    let t_bottom = (bottom - ay) / dir_y
    let t_enter = @core.js_min(t_top, t_bottom)
    let t_exit = @core.js_max(t_top, t_bottom)
    if (!parallel_x && (t_enter >= 1.0 || t_exit <= 0.0)) ||
      (parallel_x && (ay < top || ay > bottom)) {
      if by >= top && by <= bottom {
        ring.push(self.tri_ids[(e + 1) % 3])
      }
      continue
    }
    if !parallel_x && t_enter > 0.0 {
      ring.push(
        self.vertex_to_index(ax + dir_x * t_enter, ay + dir_y * t_enter),
      )
    }
    let enter_x = ax + dir_x * @core.js_max(t_enter, 0.0)
    let exit_x = ax + dir_x * @core.js_min(t_exit, 1.0)
    if !parallel_y {
      self.intra_edge_vertices(ax, ay, bx, by, enter_x, exit_x)
    }
    if !parallel_x && t_exit < 1.0 {
      ring.push(self.vertex_to_index(ax + dir_x * t_exit, ay + dir_y * t_exit))
    }
    if parallel_x || (by >= top && by <= bottom) {
      ring.push(self.tri_ids[(e + 1) % 3])
    }
    if !parallel_x && (by <= top || by >= bottom) {
      self.inter_edge_vertices(ax, ay, bx, by, cx, cy, exit_x, top, bottom)
    }
    if self.failed {
      return
    }
  }
}

///|
/// Vertices where edge a→b crosses cell columns within the row
/// (`_generateIntraEdgeVertices`).
fn Subdivider::intra_edge_vertices(
  self : Subdivider,
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  enter_x : Double,
  exit_x : Double,
) -> Unit {
  let cell = self.cell
  let dir_x = bx - ax
  let dir_y = by - ay
  let parallel_x = dir_y == 0.0
  let left_x = if parallel_x {
    @core.js_min(ax, bx)
  } else {
    @core.js_min(enter_x, exit_x)
  }
  let right_x = if parallel_x {
    @core.js_max(ax, bx)
  } else {
    @core.js_max(enter_x, exit_x)
  }
  let left = (left_x / cell).floor() + 1.0
  let right = (right_x / cell).ceil() - 1.0
  let left_to_right = if parallel_x { ax < bx } else { enter_x < exit_x }
  if left_to_right {
    for cx = left; cx <= right && !self.failed; cx = cx + 1.0 {
      let x = cx * cell
      self.ring.push(self.vertex_to_index(x, ay + dir_y * (x - ax) / dir_x))
    }
  } else {
    for cx = right; cx >= left && !self.failed; cx = cx - 1.0 {
      let x = cx * cell
      self.ring.push(self.vertex_to_index(x, ay + dir_y * (x - ax) / dir_x))
    }
  }
}

///|
/// Vertices along the row boundary between where a→b leaves the row and the
/// next edge enters it (`_generateInterEdgeVertices`).
fn Subdivider::inter_edge_vertices(
  self : Subdivider,
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
  exit_x : Double,
  top : Double,
  bottom : Double,
) -> Unit {
  let cell = self.cell
  let dir_y = by - ay
  let dir2_x = cx - bx
  let dir2_y = cy - by
  let t2_top = (top - by) / dir2_y
  let t2_bottom = (bottom - by) / dir2_y
  let t2_enter = @core.js_min(t2_top, t2_bottom)
  let t2_exit = @core.js_max(t2_top, t2_bottom)
  let enter2_x = bx + dir2_x * t2_enter
  let mut left = (@core.js_min(enter2_x, exit_x) / cell).floor() + 1.0
  let mut right = (@core.js_max(enter2_x, exit_x) / cell).ceil() - 1.0
  let mut left_to_right = exit_x < enter2_x
  let parallel_x2 = dir2_y == 0.0
  if parallel_x2 && (cy == top || cy == bottom) {
    return
  }
  if parallel_x2 || t2_enter >= 1.0 || t2_exit <= 0.0 {
    let dir3_x = ax - cx
    let dir3_y = ay - cy
    let t3_top = (top - cy) / dir3_y
    let t3_bottom = (bottom - cy) / dir3_y
    let t3_enter = @core.js_min(t3_top, t3_bottom)
    let enter3_x = cx + dir3_x * t3_enter
    left = (@core.js_min(enter3_x, exit_x) / cell).floor() + 1.0
    right = (@core.js_max(enter3_x, exit_x) / cell).ceil() - 1.0
    left_to_right = exit_x < enter3_x
  }
  let boundary_y = if dir_y > 0.0 { bottom } else { top }
  if left_to_right {
    for x = left; x <= right && !self.failed; x = x + 1.0 {
      self.ring.push(self.vertex_to_index(x * cell, boundary_y))
    }
  } else {
    for x = right; x >= left && !self.failed; x = x - 1.0 {
      self.ring.push(self.vertex_to_index(x * cell, boundary_y))
    }
  }
}

///|
/// Each ring's outline as index pairs (`_generateOutline`).
fn Subdivider::generate_outline(
  self : Subdivider,
  coords : ArrayView[Int32],
  ring_ends : ArrayView[Int32],
) -> Unit {
  let path = self.path
  let mut start = 0
  for r in 0..<ring_ends.length() {
    let end = ring_ends[r]
    path.clear()
    if self.granularity < 2 {
      for i in start..<end {
        path.push(self.remap[i])
      }
      if end - start >= 2 && ring_is_open(coords, start, end) {
        path.push(path[0])
      }
    } else {
      let points = self.points
      points.clear()
      subdivide_vertex_line(
        coords[start * 2:end * 2],
        self.granularity,
        points,
        is_ring=true,
      )
      for i = 0; i < points.length(); i = i + 2 {
        path.push(
          self.vertex_to_index(points[i].to_double(), points[i + 1].to_double()),
        )
      }
      if self.failed {
        return
      }
    }
    for i in 1..<path.length() {
      self.lines.push(path[i - 1])
      self.lines.push(path[i])
    }
    self.line_ends.push(self.lines.length())
    start = end
  }
}

///|
fn ring_is_open(coords : ArrayView[Int32], start : Int32, end : Int32) -> Bool {
  coords[start * 2] != coords[(end - 1) * 2] ||
  coords[start * 2 + 1] != coords[(end - 1) * 2 + 1]
}

///|
/// Moves vertices off the pole rows so only pole caps sit there
/// (`_ensureNoPoleVertices`; the vertex map keeps their old keys, as MapLibre's does).
fn Subdivider::ensure_no_pole_vertices(self : Subdivider) -> Unit {
  let v = self.vertices
  for i = 0; i < v.length(); i = i + 2 {
    let y = v[i + 1]
    if y == @core.NORTH_POLE_Y {
      v[i + 1] = @core.NORTH_POLE_Y + 1
    }
    if y == @core.SOUTH_POLE_Y {
      v[i + 1] = @core.SOUTH_POLE_Y - 1
    }
  }
}

///|
/// Extends the triangles' edges along the tile's top or bottom edge to the
/// poles (`_fillPoles`).
fn Subdivider::fill_poles(
  self : Subdivider,
  north : Bool,
  south : Bool,
) -> Unit {
  let v = self.vertices
  let t = self.triangles
  let extent = @core.TILE_EXTENT
  let n = t.length()
  for p = 2; p < n; p = p + 3 {
    let i0 = t[p - 2]
    let i1 = t[p - 1]
    let i2 = t[p]
    let v0x = v[i0 * 2]
    let v0y = v[i0 * 2 + 1]
    let v1x = v[i1 * 2]
    let v1y = v[i1 * 2 + 1]
    let v2x = v[i2 * 2]
    let v2y = v[i2 * 2 + 1]
    if north {
      let pole = @core.NORTH_POLE_Y
      if v0y == 0 && v1y == 0 {
        self.pole_quad(i0, i1, v0x, v1x, pole)
      }
      if v1y == 0 && v2y == 0 {
        self.pole_quad(i1, i2, v1x, v2x, pole)
      }
      if v2y == 0 && v0y == 0 {
        self.pole_quad(i2, i0, v2x, v0x, pole)
      }
    }
    if south {
      let pole = @core.SOUTH_POLE_Y
      if v0y == extent && v1y == extent {
        self.pole_quad(i0, i1, v0x, v1x, pole)
      }
      if v1y == extent && v2y == extent {
        self.pole_quad(i1, i2, v1x, v2x, pole)
      }
      if v2y == extent && v0y == extent {
        self.pole_quad(i2, i0, v2x, v0x, pole)
      }
    }
  }
}

///|
/// Two triangles from edge i0–i1 to the pole at `pole_y`, counter-clockwise
/// (`_generatePoleQuad`).
fn Subdivider::pole_quad(
  self : Subdivider,
  i0 : Int32,
  i1 : Int32,
  v0x : Int32,
  v1x : Int32,
  pole_y : Int32,
) -> Unit {
  let t = self.triangles
  let flip = (v0x > v1x) != (pole_y == @core.NORTH_POLE_Y)
  let x0 = v0x.to_double()
  let x1 = v1x.to_double()
  let y = pole_y.to_double()
  if flip {
    t.push(i0)
    t.push(i1)
    t.push(self.vertex_to_index(x0, y))
    t.push(i1)
    t.push(self.vertex_to_index(x1, y))
    t.push(self.vertex_to_index(x0, y))
  } else {
    t.push(i1)
    t.push(i0)
    t.push(self.vertex_to_index(x0, y))
    t.push(self.vertex_to_index(x1, y))
    t.push(i1)
    t.push(self.vertex_to_index(x0, y))
  }
}

///|
/// Drops, in place, the primitives of `size` indices in `indices[start:end]`
/// with a vertex beyond the tile's x range, moving later indices down
/// (`_removeTrianglesOutsideTileX`, `_removeLinesOutsideTileX`). Returns the new end.
fn remove_outside_tile_x(
  vertices : Array[Int32],
  indices : Array[Int32],
  start : Int32,
  end : Int32,
  size : Int32,
) -> Int32 {
  let extent = @core.TILE_EXTENT
  let mut w = start
  for i = start; i + size <= end; i = i + size {
    let mut outside = false
    for k in 0..<size {
      let x = vertices[indices[i + k] * 2]
      if x < 0 || x > extent {
        outside = true
      }
    }
    if !outside {
      for k in 0..<size {
        indices[w + k] = indices[i + k]
      }
      w += size
    }
  }
  let removed = end - w
  if removed > 0 {
    for i in end..<indices.length() {
      indices[i - removed] = indices[i]
    }
    indices.truncate(indices.length() - removed)
  }
  w
}

///|
/// Appends `remap`-ed triangles of `input`, each turned counter-clockwise
/// (`fixWindingOrder` of `remapIndices`).
fn fix_winding_order(
  vertices : Array[Int32],
  input : Array[Int32],
  remap : Array[Int32],
  out : Array[Int32],
) -> Unit {
  for i = 0; i + 2 < input.length(); i = i + 3 {
    let i0 = remap[input[i]]
    let i1 = remap[input[i + 1]]
    let i2 = remap[input[i + 2]]
    let v0x = vertices[i0 * 2].to_double()
    let v0y = vertices[i0 * 2 + 1].to_double()
    let e0x = vertices[i1 * 2].to_double() - v0x
    let e0y = vertices[i1 * 2 + 1].to_double() - v0y
    let e1x = vertices[i2 * 2].to_double() - v0x
    let e1y = vertices[i2 * 2 + 1].to_double() - v0y
    out.push(i0)
    if e0x * e1y - e0y * e1x > 0.0 {
      out.push(i2)
      out.push(i1)
    } else {
      out.push(i1)
      out.push(i2)
    }
  }
}

///|
/// Triangulates a convex ordered ring of vertex indices from its leftmost
/// vertex, appending to `out` (`scanlineTriangulateVertexRing`). False for an
/// empty ring, where MapLibre throws.
fn scanline_triangulate_ring(
  vertices : Array[Int32],
  ring : Array[Int32],
  out : Array[Int32],
) -> Bool {
  let n = ring.length()
  if n == 0 {
    return false
  }
  let x_of = (i : Int32) => vertices[ring[i] * 2].to_double()
  let y_of = (i : Int32) => vertices[ring[i] * 2 + 1].to_double()
  let mut leftmost = 0
  let mut leftmost_x = x_of(0)
  for i in 1..<n {
    let x = x_of(i)
    if x < leftmost_x {
      leftmost_x = x
      leftmost = i
    }
  }
  let mut edge_a = leftmost
  let mut edge_b = (edge_a + 1) % n
  while true {
    let cand_a = if edge_a - 1 >= 0 { edge_a - 1 } else { n - 1 }
    let cand_b = (edge_b + 1) % n
    let cax = x_of(cand_a)
    let cbx = x_of(cand_b)
    let pick_a = if cax < cbx {
      true
    } else if cax > cbx {
      false
    } else {
      let lax = x_of(edge_a)
      let lay = y_of(edge_a)
      let lbx = x_of(edge_b)
      let lby = y_of(edge_b)
      let nx = lby - lay
      let ny = -(lbx - lax)
      let sign = if lay < lby { 1.0 } else { -1.0 }
      let a_right = ((cax - lax) * nx + (y_of(cand_a) - lay) * ny) * sign
      let b_right = ((cbx - lax) * nx + (y_of(cand_b) - lay) * ny) * sign
      a_right > b_right
    }
    let c = if pick_a { ring[cand_a] } else { ring[cand_b] }
    let a = ring[edge_a]
    let b = ring[edge_b]
    if c != a && c != b && a != b {
      out.push(b)
      out.push(a)
      out.push(c)
    }
    if pick_a {
      edge_a -= 1
      if edge_a < 0 {
        edge_a = n - 1
      }
    } else {
      edge_b += 1
      if edge_b >= n {
        edge_b = 0
      }
    }
    if cand_a == cand_b {
      break
    }
  }
  true
}

///|
/// Appends to `out` the x, y pairs of the line through `points` (x, y pairs)
/// cut where it crosses the cell grid of `granularity` (at most `TILE_EXTENT`),
/// with the closing segment when `is_ring` and open (`subdivideVertexLine`).
pub fn subdivide_vertex_line(
  points : ArrayView[Int32],
  granularity : Int32,
  out : Array[Int32],
  is_ring~ : Bool = false,
) -> Unit {
  let n = points.length() / 2
  if n < 2 {
    return
  }
  let close = is_ring && ring_is_open(points, 0, n)
  if granularity < 2 {
    for v in points[0:n * 2] {
      out.push(v)
    }
    if close {
      out.push(points[0])
      out.push(points[1])
    }
    return
  }
  let cell = (@core.TILE_EXTENT.to_double() / granularity.to_double()).floor()
  out.push(points[0])
  out.push(points[1])
  let push_new = (x : Int32, y : Int32) => {
    let len = out.length()
    if out[len - 2] != x || out[len - 1] != y {
      out.push(x)
      out.push(y)
    }
  }
  let last = if close { n } else { n - 1 }
  for p in 0..<last {
    let q = if p < n - 1 { p + 1 } else { 0 }
    let x0 = points[p * 2].to_double()
    let y0 = points[p * 2 + 1].to_double()
    let x1 = points[q * 2].to_double()
    let y1 = points[q * 2 + 1].to_double()
    let moves_x = x0 != x1
    let moves_y = y0 != y1
    if !moves_x && !moves_y {
      continue
    }
    let dir_x = x1 - x0
    let dir_y = y1 - y0
    let abs_x = dir_x.abs()
    let abs_y = dir_y.abs()
    let mut px = x0
    let mut py = y0
    while true {
      let next_x = if dir_x > 0.0 {
        ((px / cell).floor() + 1.0) * cell
      } else {
        ((px / cell).ceil() - 1.0) * cell
      }
      let next_y = if dir_y > 0.0 {
        ((py / cell).floor() + 1.0) * cell
      } else {
        ((py / cell).ceil() - 1.0) * cell
      }
      let to_boundary_x = (px - next_x).abs()
      let to_boundary_y = (py - next_y).abs()
      let to_end_x = (px - x1).abs()
      let to_end_y = (py - y1).abs()
      let real_x = if moves_x {
        to_boundary_x / abs_x
      } else {
        @double.infinity
      }
      let real_y = if moves_y {
        to_boundary_y / abs_y
      } else {
        @double.infinity
      }
      if (to_end_x <= to_boundary_x || !moves_x) &&
        (to_end_y <= to_boundary_y || !moves_y) {
        break
      }
      if (real_x < real_y && moves_x) || !moves_y {
        px = next_x
        py = py + dir_y * real_x
        push_new(px.to_int(), @core.js_round(py).to_int())
      } else {
        px = px + dir_x * real_y
        py = next_y
        push_new(@core.js_round(px).to_int(), py.to_int())
      }
    }
    push_new(points[q * 2], points[q * 2 + 1])
  }
}
