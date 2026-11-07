// Expected values from geojson-path-finder 2.1.0 in Node, each table row's
// lines given as LineString features.

///|
fn lines_table(lines : Array[Array[(Double, Double)]]) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for line in lines {
    for p in line {
      b.point(p.0, p.1)
    }
    b.end_ring()
    b.end_part()
    b.end_feature(LineString)
  }
  b.finish()
}

///|
fn network(lines : Array[Array[(Double, Double)]]) -> @route.Network {
  @route.Network::new(lines_table(lines)).unwrap()
}

///|
/// Whether `a` is `b` within 1e-12 relative: native `@math` can differ from
/// the host's `Math` in the last bit.
fn close(a : Double, b : Double) -> Bool {
  (a - b).abs() <= b.abs() * 1.0e-12
}

///|
fn check(
  net : @route.Network,
  from : (Double, Double),
  to : (Double, Double),
  path : Array[(Double, Double)],
  weight : Double,
) -> Unit raise {
  guard net.find_path(from.0, from.1, to.0, to.1) is Some((got, w)) else {
    fail("no path")
  }
  assert_eq(got, path)
  assert_true(close(w, weight), msg="\{w} vs \{weight}")
}

///|
fn none(
  net : @route.Network,
  from : (Double, Double),
  to : (Double, Double),
) -> Unit raise {
  assert_true(net.find_path(from.0, from.1, to.0, to.1) is None)
}

///|
test "find_path on a cross" {
  let net = network([
    [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0)],
    [(1.0, -1.0), (1.0, 0.0), (1.0, 1.0)],
  ])
  assert_eq(net.vertices(), 5)
  assert_eq(net.compacted_vertices(), 5)
  check(
    net,
    (0.0, 0.0),
    (1.0, 1.0),
    [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0)],
    222.3901604670658,
  )
  check(
    net,
    (2.0, 0.0),
    (1.0, -1.0),
    [(2.0, 0.0), (1.0, 0.0), (1.0, -1.0)],
    222.3901604670658,
  )
  check(net, (1.0, 0.0), (1.0, 0.0), [(1.0, 0.0)], 0.0)
  check(net, (0.0, 0.0), (0.0, 0.0), [(0.0, 0.0)], 0.0)
  check(net, (0.0, 0.0), (0.000004, -0.000004), [(0.0, 0.0)], 0.0)
  none(net, (0.5, 0.0), (1.0, 1.0))
  none(net, (0.0, 0.0), (3.0, 3.0))
  none(net, (@double.not_a_number, 0.0), (1.0, 1.0))
}

///|
test "find_path takes the first of equal routes around a ring" {
  let tails = [[(-1.0, 0.0), (0.0, 0.0)], [(2.0, 0.0), (3.0, 0.0)]]
  let net = network(
    [[(0.0, 0.0), (1.0, 1.0), (2.0, 0.0), (1.0, -1.0), (0.0, 0.0)], ..tails],
  )
  assert_eq(net.vertices(), 6)
  assert_eq(net.compacted_vertices(), 4)
  check(
    net,
    (-1.0, 0.0),
    (3.0, 0.0),
    [(-1.0, 0.0), (0.0, 0.0), (1.0, 1.0), (2.0, 0.0), (3.0, 0.0)],
    536.8893574151462,
  )
  check(
    net,
    (0.0, 0.0),
    (2.0, 0.0),
    [(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)],
    314.4991969480804,
  )
  check(
    net,
    (1.0, 1.0),
    (1.0, -1.0),
    [(1.0, 1.0), (0.0, 0.0), (1.0, -1.0)],
    314.4991969480804,
  )
  check(
    net,
    (2.0, 0.0),
    (0.0, 0.0),
    [(2.0, 0.0), (1.0, 1.0), (0.0, 0.0)],
    314.4991969480804,
  )
  check(
    net,
    (1.0, 1.0),
    (3.0, 0.0),
    [(1.0, 1.0), (2.0, 0.0), (3.0, 0.0)],
    268.4446787075731,
  )
  let rev = network(
    [[(0.0, 0.0), (1.0, -1.0), (2.0, 0.0), (1.0, 1.0), (0.0, 0.0)], ..tails],
  )
  check(
    rev,
    (-1.0, 0.0),
    (3.0, 0.0),
    [(-1.0, 0.0), (0.0, 0.0), (1.0, -1.0), (2.0, 0.0), (3.0, 0.0)],
    536.8893574151462,
  )
  check(
    rev,
    (0.0, 0.0),
    (2.0, 0.0),
    [(0.0, 0.0), (1.0, -1.0), (2.0, 0.0)],
    314.4991969480804,
  )
  check(
    rev,
    (1.0, 1.0),
    (1.0, -1.0),
    [(1.0, 1.0), (2.0, 0.0), (1.0, -1.0)],
    314.4991969480804,
  )
}

///|
test "find_path on a ring without forks" {
  let net = network([
    [(0.0, 0.0), (1.0, 1.0), (2.0, 0.0), (1.0, -1.0), (0.0, 0.0)],
  ])
  assert_eq(net.vertices(), 4)
  assert_eq(net.compacted_vertices(), 1)
  check(
    net,
    (0.0, 0.0),
    (2.0, 0.0),
    [(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)],
    314.4991969480804,
  )
  check(
    net,
    (1.0, 1.0),
    (1.0, -1.0),
    [(1.0, 1.0), (0.0, 0.0), (1.0, -1.0)],
    314.4991969480804,
  )
  check(
    net,
    (2.0, 0.0),
    (0.0, 0.0),
    [(2.0, 0.0), (1.0, 1.0), (0.0, 0.0)],
    314.4991969480804,
  )
  check(
    net,
    (1.0, 1.0),
    (2.0, 0.0),
    [(1.0, 1.0), (2.0, 0.0)],
    157.2495984740402,
  )
}

///|
test "find_path through a dead end" {
  let net = network([
    [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)],
    [(1.0, 0.0), (1.0, 0.5), (1.0, 1.0)],
  ])
  assert_eq(net.vertices(), 6)
  assert_eq(net.compacted_vertices(), 4)
  check(
    net,
    (0.0, 0.0),
    (1.0, 1.0),
    [(0.0, 0.0), (1.0, 0.0), (1.0, 0.5), (1.0, 1.0)],
    222.3901604670658,
  )
  check(
    net,
    (1.0, 1.0),
    (3.0, 0.0),
    [(1.0, 1.0), (1.0, 0.5), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)],
    333.5852407005987,
  )
  check(
    net,
    (1.0, 0.5),
    (2.0, 0.0),
    [(1.0, 0.5), (1.0, 0.0), (2.0, 0.0)],
    166.79262035029936,
  )
  check(
    net,
    (3.0, 0.0),
    (0.0, 0.0),
    [(3.0, 0.0), (2.0, 0.0), (1.0, 0.0), (0.0, 0.0)],
    333.5852407005987,
  )
}

///|
test "find_path between disconnected parts" {
  let net = network([
    [(0.0, 0.0), (1.0, 0.0)],
    [(5.0, 5.0), (6.0, 5.0), (7.0, 5.0)],
  ])
  assert_eq(net.vertices(), 5)
  assert_eq(net.compacted_vertices(), 4)
  none(net, (0.0, 0.0), (7.0, 5.0))
  check(
    net,
    (5.0, 5.0),
    (7.0, 5.0),
    [(5.0, 5.0), (6.0, 5.0), (7.0, 5.0)],
    221.5438774047107,
  )
  check(
    net,
    (1.0, 0.0),
    (0.0, 0.0),
    [(1.0, 0.0), (0.0, 0.0)],
    111.1950802335329,
  )
}

///|
test "Network::new takes each line of a MultiLineString and skips other rows" {
  let b = @geom.TableBuilder::new()
  b.point(1.0, 1.0)
  b.end_ring()
  b.end_part()
  b.end_feature(Point)
  for line in [[(0.0, 0.0), (0.5, 0.2), (1.0, 0.0)], [(1.0, 0.0), (2.0, 0.0)]] {
    for p in line {
      b.point(p.0, p.1)
    }
    b.end_ring()
    b.end_part()
  }
  b.end_feature(MultiLineString)
  for p in [(0.0, 0.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)] {
    b.point(p.0, p.1)
  }
  b.end_ring()
  b.end_part()
  b.end_feature(Polygon)
  b.point(1.0, 0.0)
  b.point(1.0, 1.0)
  b.end_ring()
  b.end_part()
  b.end_feature(LineString)
  b.end_feature(NoGeometry)
  let net = @route.Network::new(b.finish()).unwrap()
  assert_eq(net.vertices(), 5)
  assert_eq(net.compacted_vertices(), 4)
  check(
    net,
    (0.0, 0.0),
    (2.0, 0.0),
    [(0.0, 0.0), (0.5, 0.2), (1.0, 0.0), (2.0, 0.0)],
    230.9556371299792,
  )
  check(
    net,
    (0.5, 0.2),
    (1.0, 1.0),
    [(0.5, 0.2), (1.0, 0.0), (1.0, 1.0)],
    171.07535868175606,
  )
  check(
    net,
    (2.0, 0.0),
    (0.5, 0.2),
    [(2.0, 0.0), (1.0, 0.0), (0.5, 0.2)],
    171.07535868175606,
  )
}

///|
test "Network::new merges vertices within the tolerance" {
  let net = network([
    [(139.700001, 35.6), (139.71, 35.6)],
    [(139.700004, 35.600003), (139.7, 35.61)],
    [(139.709996, 35.6), (139.71, 35.61), (139.7, 35.61)],
  ])
  assert_eq(net.vertices(), 4)
  assert_eq(net.compacted_vertices(), 1)
  check(
    net,
    (139.7, 35.6),
    (139.7, 35.61),
    [(139.700004, 35.600003), (139.7, 35.61)],
    1.1116172759165297,
  )
  check(
    net,
    (139.71, 35.6),
    (139.7, 35.61),
    [(139.709996, 35.6), (139.700004, 35.600003), (139.7, 35.61)],
    2.01502206137406,
  )
  check(
    net,
    (139.700003, 35.600002),
    (139.71, 35.61),
    [(139.700004, 35.600003), (139.709996, 35.6), (139.71, 35.61)],
    2.015355646597064,
  )
}

///|
test "Network::new refuses NaN in lines and takes empty tables" {
  let nan = @double.not_a_number
  assert_true(
    @route.Network::new(lines_table([[(0.0, 0.0), (nan, 1.0)]])) is None,
  )
  assert_true(@route.Network::new(lines_table([[(nan, 1.0)]])) is None)
  let empty = @route.Network::new(@geom.Table::new()).unwrap()
  assert_eq(empty.vertices(), 0)
  assert_eq(empty.compacted_vertices(), 0)
  none(empty, (0.0, 0.0), (0.0, 0.0))
  let points = network([[(1.0, 1.0)], [(2.0, 2.0), (2.0, 2.0)]])
  assert_eq(points.vertices(), 0)
  none(points, (1.0, 1.0), (1.0, 1.0))
  let inf = network([[(0.0, 0.0), (@double.infinity, 0.0), (1.0, 0.0)]])
  assert_eq(inf.vertices(), 0)
}

///|
test "Network::new refuses more than MAX_ROUTE_VERTICES coordinates" {
  let b = @geom.TableBuilder::new()
  for i in 0..<(@route.MAX_ROUTE_VERTICES + 1) {
    b.point(i.to_double() * 1.0e-6, 0.0)
  }
  b.end_ring()
  b.end_part()
  b.end_feature(LineString)
  assert_true(@route.Network::new(b.finish()) is None)
}

///|
/// mulberry32, as the JS that made the expected values draws numbers.
priv struct Rng {
  mut a : UInt32
}

///|
fn Rng::next(self : Rng) -> Double {
  self.a = self.a + 0x6D2B79F5U
  let a = self.a
  let mut t = (a ^ (a >> 15)) * (1U | a)
  t = (t + (t ^ (t >> 7)) * (61U | t)) ^ t
  (t ^ (t >> 14)).to_double() / 4294967296.0
}

///|
fn grid(
  seed : UInt32,
  n : Int32,
  step : Double,
  jit : Double,
) -> Array[Array[(Double, Double)]] {
  let r = { a: seed, }
  let lines = []
  for dir in 0..<2 {
    for i in 0..<n {
      let mut cur = []
      for j in 0..<n {
        let (row, col) = if dir == 0 { (i, j) } else { (j, i) }
        let bx = 139.7 + col.to_double() * step
        let by = 35.6 + row.to_double() * step
        let px = bx + (r.next() - 0.5) * jit
        let py = by + (r.next() - 0.5) * jit
        if j > 0 {
          let u = r.next()
          if u < 0.1 {
            if cur.length() >= 2 {
              lines.push(cur)
            }
            cur = []
          } else {
            let m = (r.next() * 3.0).floor().to_int()
            let (qx, qy) = cur[cur.length() - 1]
            for k in 1..<=m {
              let f = k.to_double() / (m + 1).to_double()
              let x = qx + (px - qx) * f + (r.next() - 0.5) * step * 0.2
              let y = qy + (py - qy) * f + (r.next() - 0.5) * step * 0.2
              cur.push((x, y))
            }
            if u > 0.85 {
              cur.push((px, py))
              lines.push(cur)
              cur = []
            }
          }
        }
        cur.push((px, py))
      }
      if cur.length() >= 2 {
        lines.push(cur)
      }
    }
  }
  lines
}

///|
fn queries(
  seed : UInt32,
  lines : Array[Array[(Double, Double)]],
  n : Int32,
  step : Double,
  count : Int32,
) -> Array[((Double, Double), (Double, Double))] {
  let r = { a: seed, }
  let all = lines.flatten()
  let pick = () => {
    let u = r.next()
    if u < 0.5 {
      let i = (r.next() * n.to_double()).floor()
      let j = (r.next() * n.to_double()).floor()
      (139.7 + j * step, 35.6 + i * step)
    } else if u < 0.9 {
      all[(r.next() * all.length().to_double()).floor().to_int()]
    } else {
      let x = 139.7 + r.next() * step * n.to_double()
      (x, 35.6 + r.next() * step * n.to_double())
    }
  }
  let out = []
  for _ in 0..<count {
    let a = pick()
    out.push((a, pick()))
  }
  out
}

///|
fn mix(h : UInt32, u : UInt32) -> UInt32 {
  (h ^ u) * 0x01000193U
}

///|
fn mix_double(h : UInt32, x : Double) -> UInt32 {
  let bits = x.reinterpret_as_uint64()
  mix(mix(h, (bits >> 32).to_uint()), bits.to_uint())
}

///|
/// What the JS script's `runHash` gives: the paths' hash, how many were found
/// and their weights' sum.
fn run(
  net : @route.Network,
  qs : Array[((Double, Double), (Double, Double))],
) -> (UInt32, Int32, Double) {
  let mut h = 0x811c9dc5U
  let mut found = 0
  let mut sum = 0.0
  for q in qs {
    let ((ax, ay), (bx, by)) = q
    match net.find_path(ax, ay, bx, by) {
      None => h = mix(h, 0xffffffffU)
      Some((path, w)) => {
        found += 1
        h = mix(h, path.length().reinterpret_as_uint())
        for p in path {
          h = mix_double(mix_double(h, p.0), p.1)
        }
        sum += w
      }
    }
  }
  (h, found, sum)
}

///|
test "find_path on jittered grids, hundreds of queries" {
  let cases : Array[
    (
      UInt32,
      Int32,
      Double,
      Double,
      Double,
      UInt32,
      Int32,
      Int32,
      Int32,
      UInt32,
      Int32,
      Double,
    ),
  ] = [
    (
      1, 12, 0.001, 0.8e-5, 1.0e-5, 7, 300, 362, 127, 2085864379, 245, 193.0704061157434,
    ),
    (
      2, 20, 0.001, 0.8e-4, 1.0e-4, 8, 300, 1089, 361, 2274920708, 241, 311.77704327965336,
    ),
    (
      3, 30, 0.0005, 0.8e-5, 1.0e-5, 9, 400, 2501, 822, 1006913888, 336, 345.42353871158855,
    ),
  ]
  for c in cases {
    let (
      seed,
      n,
      step,
      jit,
      tolerance,
      qseed,
      count,
      vertices,
      compacted,
      hash,
      found,
      sum,
    ) = c
    let lines = grid(seed, n, step, jit)
    let net = @route.Network::new(lines_table(lines), tolerance~).unwrap()
    assert_eq(net.vertices(), vertices)
    assert_eq(net.compacted_vertices(), compacted)
    let qs = queries(qseed, lines, n, step, count)
    let (h, f, s) = run(net, qs)
    assert_eq(f, found)
    assert_eq(h, hash)
    assert_true(close(s, sum), msg="\{s} vs \{sum}")
    let (h2, _, _) = run(net, qs)
    assert_eq(h2, hash)
  }
}

///|
test "find_path along a long line and around a star" {
  let r = { a: 11, }
  let line = []
  for i in 0..<5000 {
    let x = 139.7 + i.to_double() * 0.0001 + r.next() * 0.00002
    line.push((x, 35.6 + r.next() * 0.0001))
  }
  let net = network([line])
  assert_eq(net.vertices(), 5000)
  assert_eq(net.compacted_vertices(), 2)
  let qs = [
    (line[0], line[4999]),
    (line[1234], line[4321]),
    (line[4321], line[1234]),
    (line[10], line[11]),
    (line[2000], line[2000]),
  ]
  let (h, f, s) = run(net, qs)
  assert_eq((h, f), (1633509693, 5))
  assert_true(close(s, 112.48696774458179))
  guard net.find_path(line[4321].0, line[4321].1, line[1234].0, line[1234].1)
    is Some((_, w)) else {
    fail("no path")
  }
  assert_true(close(w, 31.082449688912593))
  let r = { a: 12, }
  let lines = []
  for _ in 0..<3000 {
    let mx = 139.7 + (r.next() - 0.5) * 0.01
    let my = 35.6 + (r.next() - 0.5) * 0.01
    let ex = mx + (r.next() - 0.5) * 0.01
    lines.push([(139.7, 35.6), (mx, my), (ex, my + (r.next() - 0.5) * 0.01)])
  }
  let net = network(lines)
  assert_eq(net.vertices(), 5996)
  assert_eq(net.compacted_vertices(), 3002)
  let qs = [
    (lines[0][2], lines[1][2]),
    (lines[5][1], lines[2999][2]),
    (lines[7][2], (139.7, 35.6)),
    (lines[100][1], lines[100][2]),
  ]
  let (h, f, s) = run(net, qs)
  assert_eq((h, f), (2167056775, 4))
  assert_true(close(s, 3.8088083787510683))
}

///|
test "Network::new and find_path on a line of 200000 points" {
  let line = []
  for i in 0..<200000 {
    line.push((i.to_double() * 1.0e-4, (i % 7).to_double() * 1.0e-4))
  }
  let net = network([line])
  assert_eq(net.compacted_vertices(), 2)
  guard net.find_path(line[3].0, line[3].1, line[199990].0, line[199990].1)
    is Some((path, _)) else {
    fail("no path")
  }
  assert_eq(path.length(), 199988)
  assert_eq(path[0], line[3])
  assert_eq(path[199987], line[199990])
}
