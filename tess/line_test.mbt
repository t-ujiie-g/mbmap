///|
/// Sum of triangle areas with outlines placed `half_width` from the center.
fn line_area(out : @tess.LineBuffers, half_width : Double) -> Double {
  let v = out.vertices
  let s = @tess.LINE_VERTEX_STRIDE
  let scale = half_width / @tess.EXTRUDE_SCALE.to_double()
  let px = (i : Int32) => {
    v[i * s].to_double() + v[i * s + 2].to_double() * scale
  }
  let py = (i : Int32) => {
    v[i * s + 1].to_double() + v[i * s + 3].to_double() * scale
  }
  for t = 0, sum = 0.0; t < out.indices.length(); t = t + 3 {
    let (a, b, c) = (out.indices[t], out.indices[t + 1], out.indices[t + 2])
    let cross = (px(b) - px(a)) * (py(c) - py(a)) -
      (px(c) - px(a)) * (py(b) - py(a))
    continue t + 3, sum + cross.abs() / 2.0
  } nobreak {
    sum
  }
}

///|
fn extrude(
  points : Array[Int32],
  join~ : @tess.LineJoin = Miter,
  cap~ : @tess.LineCap = Butt,
) -> @tess.LineBuffers {
  let out = @tess.LineBuffers::new()
  @tess.LineTessellator::new().add_line(
    points[:],
    0,
    points.length() / 2,
    out,
    join~,
    cap~,
  )
  out
}

///|
fn assert_valid(out : @tess.LineBuffers) -> Unit raise {
  let n = out.num_vertices()
  assert_eq(out.indices.length() % 3, 0)
  for i in out.indices {
    assert_true(i >= 0 && i < n)
  }
  for i in 0..<n {
    let e = out.vertices[i * @tess.LINE_VERTEX_STRIDE + 2]
    let f = out.vertices[i * @tess.LINE_VERTEX_STRIDE + 3]
    assert_true(e.abs() <= 127 && f.abs() <= 127)
  }
}

///|
fn near(a : Double, b : Double) -> Bool {
  (a - b).abs() <= 1.0e-9 * b.abs()
}

///|
test "a straight butt line covers length times width" {
  let out = extrude([0, 0, 1000, 0])
  assert_valid(out)
  assert_eq((out.num_vertices(), out.indices.length()), (4, 6))
  assert_true(near(line_area(out, 10.0), 1000.0 * 20.0))
}

///|
test "square caps add half a width at each end" {
  let out = extrude([0, 0, 0, 1000], cap=Square)
  assert_valid(out)
  assert_true(near(line_area(out, 10.0), (1000.0 + 20.0) * 20.0))
}

///|
test "a right-angle miter shares one pair and covers both arms exactly" {
  let out = extrude([0, 0, 1000, 0, 1000, 500])
  assert_valid(out)
  assert_eq(out.num_vertices(), 6)
  assert_true(near(line_area(out, 10.0), (1000.0 + 500.0) * 20.0))
  // The shared pair sits on the miter, sqrt(2) half widths out.
  let s = @tess.LINE_VERTEX_STRIDE
  assert_eq((out.vertices[2 * s + 2], out.vertices[2 * s + 3]), (-63, 63))
}

///|
test "bevel and over-limit miter joins fill the outer corner with one triangle" {
  // The arms' quads sum to both arms' length times width (their inner-corner
  // overlap counted twice); the fill adds half a corner square.
  let expected = (1000.0 + 500.0) * 20.0 + 10.0 * 10.0 / 2.0
  let bevel = extrude([0, 0, 1000, 0, 1000, 500], join=Bevel)
  assert_valid(bevel)
  assert_true(near(line_area(bevel, 10.0), expected))
  // A hairpin's miter is far over the limit, so it falls back to a bevel.
  let hairpin = extrude([0, 0, 1000, 0, 0, 10])
  assert_valid(hairpin)
  assert_true(hairpin.num_vertices() > 6)
}

///|
test "round caps and joins add fans close to the circle area" {
  let capped = extrude([0, 0, 1000, 0], cap=Round)
  assert_valid(capped)
  let half_disk = @math.PI * 10.0 * 10.0 / 2.0
  let area = line_area(capped, 10.0)
  let body = 1000.0 * 20.0
  assert_true(area > body + 2.0 * half_disk * 0.95)
  assert_true(area < body + 2.0 * half_disk)
  let joined = extrude([0, 0, 1000, 0, 1000, 500], join=Round)
  assert_valid(joined)
  // Quarter-circle fill on top of the bevel-style arms.
  let quarter = @math.PI * 10.0 * 10.0 / 4.0
  let base = (1000.0 + 500.0) * 20.0
  let joined_area = line_area(joined, 10.0)
  assert_true(
    joined_area > base + quarter * 0.95 && joined_area < base + quarter,
  )
}

///|
test "closed rings join at the start and have no caps" {
  let ring = [0, 0, 1000, 0, 1000, 1000, 0, 1000, 0, 0]
  let out = extrude(ring, cap=Round)
  assert_valid(out)
  // Three shared miter pairs, the start pair and the closing end pair, plus
  // the closing join's center and miter tip; no cap fans.
  assert_eq(out.num_vertices(), 5 * 2 + 2)
  assert_true(line_area(out, 10.0) > 4.0 * 1000.0 * 20.0)
}

///|
test "repeated and single points produce nothing" {
  assert_eq(extrude([5, 5]).num_vertices(), 0)
  assert_eq(extrude([5, 5, 5, 5, 5, 5]).num_vertices(), 0)
  let deduped = extrude([0, 0, 0, 0, 100, 0, 100, 0])
  assert_eq(deduped.num_vertices(), 4)
}

///|
test "miter limits beyond the Int8 range are clamped" {
  let out = @tess.LineBuffers::new()
  @tess.LineTessellator::new().add_line(
    [0, 0, 1000, 0, 0, 300][:],
    0,
    3,
    out,
    miter_limit=50.0,
  )
  assert_valid(out)
}
