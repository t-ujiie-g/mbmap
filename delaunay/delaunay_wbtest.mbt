///|
/// The LCG of the reference scripts: `n` x, y pairs in [0, scale).
fn lcg(
  seed : Int32,
  n : Int32,
  scale~ : Double = 1.0,
  int~ : Bool = false,
) -> FixedArray[Double] {
  let mut s = seed
  FixedArray::makei(n * 2, _ => {
    s = s * 1664525 + 1013904223
    let v = s.reinterpret_as_uint().to_double() / 4294967296.0 * scale
    if int {
      v.floor()
    } else {
      v
    }
  })
}

///|
/// FNV-1a over 32-bit words, as the reference scripts hash results.
struct Hash {
  mut h : Int32
}

///|
fn Hash::new() -> Hash {
  { h: -2128831035, }
}

///|
fn Hash::word(self : Hash, w : Int32) -> Unit {
  self.h = (self.h ^ w) * 16777619
}

///|
fn Hash::dbl(self : Hash, x : Double) -> Unit {
  let b = x.reinterpret_as_int64()
  self.word(b.to_int())
  self.word((b >> 32).to_int())
}

///|
fn ints(a : FixedArray[Int32]) -> Int32 {
  let h = Hash::new()
  for v in a {
    h.word(v)
  }
  h.h
}

///|
/// The reference script's `summary`: delaunator's lengths and hashes, then
/// d3-delaunay's triangle count and hash, null cells and cells' hash.
fn summary(
  coords : FixedArray[Double],
  bounds : (Double, Double, Double, Double),
) -> Array[Int32] {
  let d = Delaunator::new(coords.copy())
  let del = Delaunay::new(coords.copy(), @core.Trig::moonbit())
  let hp = Hash::new()
  let ntri = del.triangles.length() / 3
  for i in 0..<ntri {
    let (x0, y0, x1, y1, x2, y2) = del.triangle_points(i)
    for v in [x0, y0, x1, y1, x2, y2, x0, y0] {
      hp.dbl(v)
    }
  }
  let v = Voronoi::new(del, bounds.0, bounds.1, bounds.2, bounds.3)
  let hv = Hash::new()
  let mut nulls = 0
  for i in 0..<(coords.length() / 2) {
    match v.cell_polygon(i) {
      None => {
        hv.word(-1)
        nulls += 1
      }
      Some(c) => {
        hv.word(c.length() / 2)
        for x in c {
          hv.dbl(x)
        }
      }
    }
  }
  [
    d.triangles.length(),
    ints(d.triangles),
    ints(d.halfedges),
    d.hull.length(),
    ints(d.hull),
    ntri,
    hp.h,
    nulls,
    hv.h,
  ]
}

///|
test "random points match delaunator and d3-delaunay" {
  assert_eq(summary(lcg(1, 1000), (-0.1, -0.1, 1.1, 1.1)), [
    5937, -160021887, 1965738426, 19, 192633748, 1979, 1367206851, 0, -793440176,
  ])
  assert_eq(summary(lcg(1, 1000), (0.2, 0.3, 0.7, 0.8)), [
    5937, -160021887, 1965738426, 19, 192633748, 1979, 1367206851, 694, 1727785739,
  ])
}

///|
test "integer points with duplicates and cocircular ties match" {
  let pts = lcg(7, 500, scale=20.0, int=true)
  assert_eq(summary(pts, (-1.0, -1.0, 21.0, 21.0)), [
    1569, 724697248, -290775627, 53, -346237263, 523, -833119867, 211, -1515810961,
  ])
  assert_eq(summary(pts, (3.0, 4.0, 15.0, 9.0)), [
    1569, 724697248, -290775627, 53, -346237263, 523, -833119867, 439, 284510831,
  ])
}

///|
test "20000 random points match" {
  assert_eq(summary(lcg(42, 20000, scale=1000.0), (0.0, 0.0, 1000.0, 1000.0)), [
    119916, -1067601576, 924540281, 26, 2055647051, 39972, -1231899798, 0, -1088353804,
  ])
}

///|
test "hostile inputs match: collinear, overflowing, underflowing, duplicates" {
  let col = lcg(3, 100)
  for i in 0..<100 {
    col[2 * i + 1] = 2.0 * col[2 * i] + 1.0
  }
  assert_eq(summary(col, (-1.0, -1.0, 4.0, 4.0)), [
    0, -2128831035, -2128831035, 100, -823568101, 96, 233301562, 72, -1473973572,
  ])
  let hull_only = [
    0, -2128831035, -2128831035, 300, -348191873, 0, -2128831035, 300, -850155735,
  ]
  let big = lcg(5, 300).map(v => v * 1.0e150)
  assert_eq(summary(big, (0.0, 0.0, 1.0e150, 1.0e150)), hull_only)
  let tiny = lcg(5, 300).map(v => v * 1.0e-300)
  assert_eq(summary(tiny, (0.0, 0.0, 1.0e-300, 1.0e-300)), hull_only)
  let huge = lcg(5, 300).map(v => (v - 0.5) * 1.0e308)
  assert_eq(summary(huge, (-1.0e308, -1.0e308, 1.0e308, 1.0e308)), hull_only)
  assert_eq(summary(lcg(9, 300, scale=3.0, int=true), (0.0, 0.0, 2.0, 2.0)), [
    24, -1684482390, 107521960, 8, 1550962650, 8, 186988485, 291, -1522515905,
  ])
}
