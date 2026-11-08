///|
/// One label on an L-shaped line: (0, 0) to (10, 0) to (10, 10), its anchor on
/// the first segment.
fn l_line() -> LineSet {
  {
    meta: [0.0, 0.0, 0.0, 3.0, 0.0, 12.0],
    lines: [0.0, 0.0, 10.0, 0.0, 10.0, 10.0],
    offsets: [-2.0, 0.0, 2.0],
    keep_upright: true,
    glyphs: FixedArray::make(9, HIDDEN_GLYPH),
    laid: None,
    laid_round: -1,
    at_x: 0.0,
    at_y: 0.0,
    at_angle: 0.0,
  }
}

///|
/// `LineSet::along`'s point and angle, or None past the line's end.
fn walk(
  l : LineSet,
  offset : Double,
  flip : Bool,
  path : Array[Double]?,
) -> (Double, Double, Double)? {
  if l.along(0, 6.0, 0.0, offset, flip, path) {
    Some((l.at_x, l.at_y, l.at_angle))
  } else {
    None
  }
}

///|
test "glyphs walk along the line from the anchor, round corners and back" {
  let l = l_line()
  // Forward from (6, 0): past the corner, 2 down the second segment.
  let path = []
  assert_eq(walk(l, 6.0, false, Some(path)), Some((10.0, 2.0, @math.PI / 2.0)))
  assert_eq(path, [6.0, 0.0, 10.0, 0.0, 10.0, 2.0])
  // Backward: turned half way round, then by the reversed segment.
  assert_eq(walk(l, -4.0, false, None), Some((2.0, 0.0, 2.0 * @math.PI)))
  // Flipped, a positive offset goes backward.
  assert_eq(walk(l, 4.0, true, None), Some((2.0, 0.0, 3.0 * @math.PI)))
  // Past either end there is no room.
  assert_eq(walk(l, 15.0, false, None), None)
  assert_eq(walk(l, -7.0, false, None), None)
}

///|
test "hide_glyphs hides only the label's quads" {
  let glyphs = FixedArray::make(12, 1.0)
  hide_glyphs(glyphs, 1, 2)
  assert_eq(glyphs[0], 1.0)
  assert_eq(
    (glyphs[3], glyphs[4], glyphs[6]),
    (HIDDEN_GLYPH, 1.0, HIDDEN_GLYPH),
  )
  assert_eq(glyphs[9], 1.0)
}

///|
test "paths are cut to the box with rounded new ends" {
  assert_eq(clip_path([-10.0, 0.5, 10.0, 0.5], 0.0, 0.0, 5.0, 5.0), [
    [0.0, 1.0, 5.0, 1.0],
  ])
  // Out and back in: two parts.
  assert_eq(
    clip_path([1.0, 1.0, 1.0, 10.0, 3.0, 10.0, 3.0, 1.0], 0.0, 0.0, 5.0, 5.0),
    [[1.0, 1.0, 1.0, 5.0], [3.0, 5.0, 3.0, 1.0]],
  )
  assert_eq(clip_path([6.0, 6.0, 8.0, 8.0], 0.0, 0.0, 5.0, 5.0), [])
}

///|
test "circles cover the path as MapLibre's interpolator spaces them" {
  let out = []
  // 100 px long with radius 10: padded by 2.5 at both ends, 5 circles 23.75 apart.
  circles_along([0.0, 0.0, 100.0, 0.0], 10.0, out)
  assert_eq(out.length(), 15)
  assert_eq([out[0], out[3], out[12]], [2.5, 26.25, 97.5])
  assert_eq(out[2], 10.0)
  // A path shorter than half the radius gets one circle, past its padding.
  out.clear()
  circles_along([5.0, 5.0, 6.0, 5.0], 10.0, out)
  assert_eq(out, [5.5, 5.0, 10.0])
}

///|
test "longest_unhidden keeps the longest run of points the globe does not hide" {
  let path = [0.0, 0.0, 1.0, 1.0, 2.0, 2.0, 3.0, 3.0, 4.0, 4.0, 5.0, 5.0]
  let depths = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
  let (kept, ahead) = longest_unhidden(path, depths, [
    false, true, false, false, false, true,
  ])
  assert_eq(kept, [2.0, 2.0, 3.0, 3.0, 4.0, 4.0])
  assert_true(ahead)
  // A point of the run behind the camera leaves no path to place on.
  let (_, ahead) = longest_unhidden(path, [1.0, 1.0, 1.0, -1.0, 1.0, 1.0], [
    false, true, false, false, false, true,
  ])
  assert_false(ahead)
  let (none, _) = longest_unhidden(path, depths, [
    true, true, true, true, true, true,
  ])
  assert_eq(none, [])
}
