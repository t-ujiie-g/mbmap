///|
fn square(x : Int64, y : Int64, s : Int64) -> Array[@clipper.Point64] {
  [{ x, y, }, { x: x + s, y, }, { x: x + s, y: y + s, }, { x, y: y + s, }]
}

///|
fn total_area(paths : Array[Array[@clipper.Point64]]) -> Double {
  paths.fold(init=0.0, (s, p) => s + @clipper.area(p[:]))
}

///|
test "area is signed by orientation and point_in_polygon tells on, in and out" {
  let s = square(0L, 0L, 10L)
  assert_eq(@clipper.area(s[:]), 100.0)
  let r = s.copy()
  r.rev_in_place()
  assert_eq(@clipper.area(r[:]), -100.0)
  assert_eq(@clipper.area(s[:2]), 0.0)
  assert_eq(@clipper.point_in_polygon({ x: 5L, y: 5L, }, s[:]), IsInside)
  assert_eq(@clipper.point_in_polygon({ x: 10L, y: 5L, }, s[:]), IsOn)
  assert_eq(@clipper.point_in_polygon({ x: 11L, y: 5L, }, s[:]), IsOutside)
}

///|
test "boolean operations of two overlapping squares" {
  let a = [square(0L, 0L, 10L)]
  let b = [square(5L, 5L, 10L)]
  assert_eq(total_area(@clipper.union(a, b, NonZero)), 175.0)
  assert_eq(total_area(@clipper.intersect(a, b, NonZero)), 25.0)
  assert_eq(total_area(@clipper.difference(a, b, NonZero)), 75.0)
  assert_eq(total_area(@clipper.xor(a, b, NonZero)), 150.0)
  assert_eq(@clipper.intersect(a, b, NonZero), [
    [
      { x: 10L, y: 10L, },
      { x: 5L, y: 10L, },
      { x: 5L, y: 5L, },
      { x: 10L, y: 5L, },
    ],
  ])
  assert_eq(@clipper.boolean_op(NoClip, NonZero, a, b), [])
}

///|
test "Clipper64 clips open paths and can be cleared" {
  let c = @clipper.Clipper64::new()
  let open : Array[Array[@clipper.Point64]] = [
    [{ x: -5L, y: 5L, }, { x: 15L, y: 5L, }],
  ]
  c.add_open_subject(open)
  c.add_clip([square(0L, 0L, 10L)])
  let (closed, open) = c.execute(Intersection, NonZero).unwrap()
  assert_eq(closed, [])
  assert_eq(open, [[{ x: 0L, y: 5L, }, { x: 10L, y: 5L, }]])
  c.clear()
  assert_eq(c.execute(Intersection, NonZero), Some(([], [])))
}

///|
test "collinear points are kept unless told otherwise, and solutions can be reversed" {
  // A square with an extra point halfway along its bottom edge.
  let path : Array[@clipper.Point64] = [
    { x: 0L, y: 0L, },
    { x: 5L, y: 0L, },
    { x: 10L, y: 0L, },
    { x: 10L, y: 10L, },
    { x: 0L, y: 10L, },
  ]
  let run = (preserve : Bool, reverse : Bool) => {
    let c = @clipper.Clipper64::new()
    c.set_preserve_collinear(preserve)
    c.set_reverse_solution(reverse)
    c.add_subject([path])
    c.execute(Union, NonZero).unwrap().0
  }
  assert_eq(run(true, false)[0].length(), 5)
  assert_eq(run(false, false)[0].length(), 4)
  assert_eq(total_area(run(true, false)), 100.0)
  assert_eq(total_area(run(true, true)), -100.0)
}

///|
test "execute_tree nests holes under their outer polygons" {
  let c = @clipper.Clipper64::new()
  let hole = square(2L, 2L, 6L)
  hole.rev_in_place()
  c.add_subject([square(0L, 0L, 10L), hole, square(4L, 4L, 2L)])
  let (root, open) = c.execute_tree(Union, NonZero).unwrap()
  assert_eq(open, [])
  assert_eq(
    (root.level(), root.is_hole(), root.children.length()),
    (0, false, 1),
  )
  let outer = root.children[0]
  assert_eq(
    (outer.level(), outer.is_hole(), @clipper.area(outer.polygon[:])),
    (1, false, 100.0),
  )
  let inner = outer.children[0]
  assert_eq(
    (inner.level(), inner.is_hole(), @clipper.area(inner.polygon[:])),
    (2, true, -36.0),
  )
  let island = inner.children[0]
  assert_eq(
    (island.level(), island.is_hole(), island.children.length()),
    (3, false, 0),
  )
  assert_eq(@clipper.PolyPath64::new().children.length(), 0)
}

///|
test "inflate_paths grows and shrinks polygons and buffers lines" {
  let s = [square(0L, 0L, 10L)]
  // Miter joins keep a square's corners.
  assert_eq(total_area(@clipper.inflate_paths(s, 1.0, Miter, Polygon)), 144.0)
  assert_eq(total_area(@clipper.inflate_paths(s, -1.0, Miter, Polygon)), 64.0)
  assert_eq(@clipper.inflate_paths(s, 0.0, Miter, Polygon), s)
  // Round joins approximate quarter circles: 1000² + 4 x 1000 x 100 + π x 100².
  let big = [square(0L, 0L, 1000L)]
  let round = total_area(@clipper.inflate_paths(big, 100.0, Round, Polygon))
  // The arcs are chords within the default tolerance (delta / 500).
  assert_true(round < 1431415.9 && round > 1431415.9 - 200.0)
  // A 10-unit line with butt ends, 2 units each side.
  let line : Array[Array[@clipper.Point64]] = [
    [{ x: 0L, y: 0L, }, { x: 10L, y: 0L, }],
  ]
  assert_eq(
    total_area(@clipper.inflate_paths(line, 2.0, Square, Butt)).abs(),
    40.0,
  )
  // A point becomes a square of side 2 * ceil(delta).
  let point : Array[Array[@clipper.Point64]] = [[{ x: 0L, y: 0L, }]]
  assert_eq(
    total_area(@clipper.inflate_paths(point, 2.5, Square, Polygon)).abs(),
    36.0,
  )
}

///|
test "ClipperOffset offsets several groups at once" {
  let o = @clipper.ClipperOffset::new(miter_limit=3.0)
  o.add_paths([square(0L, 0L, 10L)], Miter, Polygon)
  o.add_paths([square(100L, 0L, 10L)], Miter, Polygon)
  o.add_paths([], Miter, Polygon)
  assert_eq(total_area(o.execute(1.0)), 288.0)
  assert_eq(@clipper.ClipperOffset::new().execute(1.0), [])
}
