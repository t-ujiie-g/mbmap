// Ring classification ports `classifyRings` from @maplibre/maplibre-gl-style-spec
// 26.5.0 (src/util/classify_rings.ts), BSD 3-Clause License, Copyright (c) 2020,
// MapLibre contributors. See NOTICE for the full license text.

///|
/// Most rings triangulated per polygon (outer ring plus largest holes), as in
/// MapLibre's fill bucket: earcut slows down with many holes.
pub const MAX_POLYGON_RINGS : Int32 = 500

///|
/// Fill geometry: `vertices` holds x, y pairs in tile units and `indices`
/// holds triangles as vertex index triples.
pub struct FillBuffers {
  vertices : Array[Int32]
  indices : Array[Int32]
}

///|
pub fn FillBuffers::new() -> FillBuffers {
  { vertices: [], indices: [], }
}

///|
pub fn FillBuffers::clear(self : FillBuffers) -> Unit {
  self.vertices.clear()
  self.indices.clear()
}

///|
pub fn FillBuffers::num_vertices(self : FillBuffers) -> Int32 {
  self.vertices.length() / 2
}

///|
/// Triangulates polygon features. Reuse one instance; its scratch buffers keep
/// their capacity, so steady-state use does not allocate.
pub struct FillTessellator {
  priv earcut : Earcut
  priv areas : Array[Double]
  priv polygon_rings : Array[Int32]
  priv polygon_starts : Array[Int32]
  priv flat : Array[Int32]
  priv hole_starts : Array[Int32]
  priv triangles : Array[Int32]
}

///|
pub fn FillTessellator::new() -> FillTessellator {
  {
    earcut: Earcut::new(),
    areas: [],
    polygon_rings: [],
    polygon_starts: [],
    flat: [],
    hole_starts: [],
    triangles: [],
  }
}

///|
/// Signed area of the ring of points `[start, end)` of `coords` (x, y pairs),
/// positive for clockwise rings in tile coordinates (y down).
pub fn ring_area(
  coords : ArrayView[Int32],
  start : Int32,
  end : Int32,
) -> Double {
  for i = start, j = end - 1, sum = 0.0; i < end; i = i + 1 {
    let d = (coords[j * 2] - coords[i * 2]).to_double() *
      (coords[i * 2 + 1].to_double() + coords[j * 2 + 1].to_double())
    continue i + 1, i, sum + d
  } nobreak {
    sum
  }
}

///|
/// Tessellates one polygon feature's rings (as in `@mvt.Geometry`) into `out`,
/// grouped like MapLibre's `classifyRings`: a ring wound like the first starts
/// a polygon, others are its holes, zero-area rings are dropped.
pub fn FillTessellator::add_polygons(
  self : FillTessellator,
  coords : ArrayView[Int32],
  ring_ends : ArrayView[Int32],
  out : FillBuffers,
) -> Unit {
  self.classify(coords, ring_ends)
  for p in 0..<(self.polygon_starts.length() - 1) {
    self.add_polygon(
      coords,
      ring_ends,
      self.polygon_starts[p],
      self.polygon_starts[p + 1],
      out,
    )
  }
}

///|
/// Fills `polygon_rings` with ring ids grouped per polygon; polygon `p` owns
/// `polygon_rings[polygon_starts[p]..polygon_starts[p + 1]]`, outer ring first.
fn FillTessellator::classify(
  self : FillTessellator,
  coords : ArrayView[Int32],
  ring_ends : ArrayView[Int32],
) -> Unit {
  let rings = self.polygon_rings
  let starts = self.polygon_starts
  let areas = self.areas
  rings.clear()
  starts.clear()
  areas.clear()
  let n = ring_ends.length()
  if n <= 1 {
    // MapLibre returns a lone ring as a polygon even if it has no area.
    starts.push(0)
    if n == 1 {
      rings.push(0)
      areas.push(0.0)
      starts.push(1)
    }
    return
  }
  let mut first_ccw = false
  let mut seen = false
  for r in 0..<n {
    let start = if r == 0 { 0 } else { ring_ends[r - 1] }
    let area = ring_area(coords, start, ring_ends[r])
    if area == 0.0 {
      continue
    }
    let ccw = area < 0.0
    if !seen {
      first_ccw = ccw
      seen = true
    }
    if ccw == first_ccw {
      starts.push(rings.length())
    }
    rings.push(r)
    areas.push(area.abs())
  }
  starts.push(rings.length())
  for p in 0..<(starts.length() - 1) {
    let s = starts[p]
    if starts[p + 1] - s > MAX_POLYGON_RINGS {
      self.keep_largest_holes(s, starts[p + 1])
    }
  }
}

///|
/// Moves the `MAX_POLYGON_RINGS - 1` largest holes of the polygon at
/// `[s, e)` of `polygon_rings` right after its outer ring. MapLibre selects
/// the same rings with quickselect, so their order (not the area) may differ.
fn FillTessellator::keep_largest_holes(
  self : FillTessellator,
  s : Int32,
  e : Int32,
) -> Unit {
  let rings = self.polygon_rings
  let areas = self.areas
  for i in (s + 2)..<e {
    let r = rings[i]
    let a = areas[i]
    let mut j = i - 1
    while j > s && areas[j] < a {
      rings[j + 1] = rings[j]
      areas[j + 1] = areas[j]
      j -= 1
    }
    rings[j + 1] = r
    areas[j + 1] = a
  }
}

///|
fn FillTessellator::add_polygon(
  self : FillTessellator,
  coords : ArrayView[Int32],
  ring_ends : ArrayView[Int32],
  first : Int32,
  last : Int32,
  out : FillBuffers,
) -> Unit {
  let flat = self.flat
  let holes = self.hole_starts
  flat.clear()
  holes.clear()
  let count = @cmp.minimum(last - first, MAX_POLYGON_RINGS)
  for k in 0..<count {
    let r = self.polygon_rings[first + k]
    let start = if r == 0 { 0 } else { ring_ends[r - 1] }
    if k > 0 {
      holes.push(flat.length() / 2)
    }
    for i in (start * 2)..<(ring_ends[r] * 2) {
      flat.push(coords[i])
    }
  }
  let tris = self.triangles
  tris.clear()
  self.earcut.triangulate(flat[:], holes[:], tris)
  let base = out.num_vertices()
  for v in flat {
    out.vertices.push(v)
  }
  for t in tris {
    out.indices.push(base + t)
  }
}
