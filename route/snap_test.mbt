///|
/// `snap_lines` of `lines` within `snap` meters, as lists of points.
fn snapped(
  lines : Array[Array[(Double, Double)]],
  snap : Double,
) -> Array[Array[(Double, Double)]]? {
  let coords = []
  let ranges = []
  for line in lines {
    let start = coords.length() / 2
    for p in line {
      coords.push(p.0)
      coords.push(p.1)
    }
    ranges.push((start, coords.length() / 2))
  }
  guard @route.snap_lines(coords, ranges, snap) is Some((out, rs)) else {
    return None
  }
  Some(
    rs.map(r => {
      Array::makei(r.1 - r.0, i => (out[(r.0 + i) * 2], out[(r.0 + i) * 2 + 1]))
    }),
  )
}

///|
test "snap_lines splits a segment where a line ends beside it" {
  let lines = [[(0.0, 0.0), (0.001, 0.0)], [(0.0005, 0.00001), (0.0005, 0.001)]]
  assert_eq(
    snapped(lines, 2.0),
    Some([
      [(0.0, 0.0), (0.0005, 0.0), (0.001, 0.0)],
      [(0.0005, 0.0), (0.0005, 0.001)],
    ]),
  )
  assert_eq(snapped(lines, 1.0), Some(lines))
  assert_eq(snapped(lines, 0.0), Some(lines))
}

///|
test "snap_lines joins ends near each other at the first" {
  let lines = [[(0.0, 0.0), (0.001, 0.0)], [(0.00101, 0.000005), (0.002, 0.0)]]
  assert_eq(
    snapped(lines, 2.0),
    Some([[(0.0, 0.0), (0.001, 0.0)], [(0.001, 0.0), (0.002, 0.0)]]),
  )
}

///|
test "snap_lines leaves a line's own end and short lines alone" {
  let short = [[(0.0, 0.0), (0.000005, 0.0), (0.00001, 0.0)]]
  assert_eq(snapped(short, 2.0), Some(short))
  let bend = [[(0.0, 0.0), (0.00001, 0.0), (0.00001, 0.00001), (0.0, 0.00001)]]
  assert_eq(snapped(bend, 2.0), Some(bend))
}

///|
test "snap_lines closes a loop and joins a line to its own far part" {
  let ring = [[(0.0, 0.0), (0.001, 0.0), (0.001, 0.001), (0.0, 0.00001)]]
  assert_eq(
    snapped(ring, 2.0),
    Some([[(0.0, 0.0), (0.001, 0.0), (0.001, 0.001), (0.0, 0.0)]]),
  )
  let p = [
    [(0.0, 0.0), (0.0, 0.002), (0.001, 0.002), (0.001, 0.001), (0.00001, 0.001)],
  ]
  assert_eq(
    snapped(p, 2.0),
    Some([
      [
        (0.0, 0.0),
        (0.0, 0.001),
        (0.0, 0.002),
        (0.001, 0.002),
        (0.001, 0.001),
        (0.0, 0.001),
      ],
    ]),
  )
}

///|
test "snap_lines keeps an end that already meets a vertex" {
  let lines = [
    [(0.0, 0.0), (0.001, 0.0), (0.002, 0.0)],
    [(0.001, 0.001), (0.001, 0.0)],
    [(0.0005, 0.00001), (0.0015, 0.00001)],
  ]
  assert_eq(
    snapped(lines, 2.0),
    Some([
      [(0.0, 0.0), (0.0005, 0.0), (0.001, 0.0), (0.0015, 0.0), (0.002, 0.0)],
      [(0.001, 0.001), (0.001, 0.0)],
      [(0.0005, 0.0), (0.0015, 0.0)],
    ]),
  )
}

///|
test "snap_lines refuses coordinates that are not finite" {
  assert_eq(snapped([[(0.0, 0.0), (@double.infinity, 0.0)]], 2.0), None)
}

///|
test "Network::new with snap routes through a T-junction" {
  let t = lines_table([
    [(139.7, 35.6), (139.701, 35.6)],
    [(139.7005, 35.60001), (139.7005, 35.601)],
  ])
  let without = @route.Network::new(t).unwrap()
  none(without, (139.7, 35.6), (139.7005, 35.601))
  let net = @route.Network::new(t, snap=2.0).unwrap()
  assert_eq(net.vertices(), 4)
  guard net.find_path(139.7, 35.6, 139.7005, 35.601) is Some((path, _)) else {
    fail("no path")
  }
  assert_eq(path, [(139.7, 35.6), (139.7005, 35.6), (139.7005, 35.601)])
  assert_eq(
    @route.Network::new(t, snap=0.0).unwrap().vertices(),
    without.vertices(),
  )
}

///|
test "Network::new with snap is None for lines it cannot snap" {
  let t = lines_table([[(0.0, 0.0), (@double.infinity, 0.0)]])
  assert_true(@route.Network::new(t, snap=2.0) is None)
}
