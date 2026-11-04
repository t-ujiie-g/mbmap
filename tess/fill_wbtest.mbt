///|
fn square(x : Int32, y : Int32, size : Int32, clockwise : Bool) -> Array[Int32] {
  if clockwise {
    [x, y, x + size, y, x + size, y + size, x, y + size, x, y]
  } else {
    [x, y, x, y + size, x + size, y + size, x + size, y, x, y]
  }
}

///|
test "signed_area is positive for clockwise rings in y-down tile space" {
  let cw = square(0, 0, 10, true)
  assert_eq(signed_area(cw[:], 0, 10), 200.0)
  let ccw = square(0, 0, 10, false)
  assert_eq(signed_area(ccw[:], 0, 10), -200.0)
}

///|
test "only the largest holes are kept beyond MAX_POLYGON_RINGS" {
  let coords = square(0, 0, 100000, true)
  let ring_ends = [5]
  // Holes of growing size; the smallest ones must be dropped.
  let holes = MAX_POLYGON_RINGS + 9
  for h in 0..<holes {
    let x = h % 100 * 900 + 10
    let y = h / 100 * 900 + 10
    for v in square(x, y, 10 + h % 7, false) {
      coords.push(v)
    }
    ring_ends.push(coords.length() / 2)
  }
  let out = FillBuffers::new()
  FillTessellator::new().add_polygons(coords[:], ring_ends[:], out)
  assert_eq(out.num_vertices(), MAX_POLYGON_RINGS * 5)
}

///|
test "signed_area keeps its sign for rings wider than Int32 differences hold" {
  let a = 1_500_000_000
  let cw = [-a, -a, a, -a, a, a, -a, a, -a, -a]
  assert_eq(signed_area(cw[:], 0, 10), 8.0 * a.to_double() * a.to_double())
}
