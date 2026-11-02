///|
let square : @core.Line = [
  (0.0, 0.0),
  (10.0, 0.0),
  (10.0, 10.0),
  (0.0, 10.0),
  (0.0, 0.0),
]

///|
test "polygon_hits_polygons: a point tests containment, even-odd over the rings" {
  let hole : @core.Line = [
    (3.0, 3.0),
    (7.0, 3.0),
    (7.0, 7.0),
    (3.0, 7.0),
    (3.0, 3.0),
  ]
  assert_true(@core.polygon_hits_polygons([(1.0, 1.0)], [square, hole]))
  assert_false(@core.polygon_hits_polygons([(5.0, 5.0)], [square, hole]))
  assert_false(@core.polygon_hits_polygons([(11.0, 5.0)], [square]))
  // A box overlapping an edge, and one around the whole square.
  let edge : @core.Line = [
    (8.0, 2.0),
    (12.0, 2.0),
    (12.0, 4.0),
    (8.0, 4.0),
    (8.0, 2.0),
  ]
  assert_true(@core.polygon_hits_polygons(edge, [square]))
  let around : @core.Line = [
    (-1.0, -1.0),
    (11.0, -1.0),
    (11.0, 11.0),
    (-1.0, 11.0),
    (-1.0, -1.0),
  ]
  assert_true(@core.polygon_hits_polygons(around, [square]))
  let apart : @core.Line = [
    (20.0, 20.0),
    (30.0, 20.0),
    (30.0, 30.0),
    (20.0, 20.0),
  ]
  assert_false(@core.polygon_hits_polygons(apart, [square]))
}

///|
test "polygon_hits_polygon crosses edges and holds either inside the other" {
  let inner : @core.Line = [(2.0, 2.0), (3.0, 2.0), (3.0, 3.0), (2.0, 2.0)]
  assert_true(@core.polygon_hits_polygon(inner, square))
  assert_true(@core.polygon_hits_polygon(square, inner))
  let cross : @core.Line = [
    (5.0, -5.0),
    (6.0, -5.0),
    (6.0, 15.0),
    (5.0, 15.0),
    (5.0, -5.0),
  ]
  assert_true(@core.polygon_hits_polygon(cross, square))
  assert_false(
    @core.polygon_hits_polygon([(20.0, 0.0), (21.0, 0.0), (21.0, 1.0)], square),
  )
}

///|
test "polygon_hits_lines is within the radius of a line, or holds one of its points" {
  let line : @core.Line = [(0.0, 0.0), (10.0, 0.0)]
  assert_true(@core.polygon_hits_lines([(5.0, 1.5)], [line], 2.0))
  assert_false(@core.polygon_hits_lines([(5.0, 2.5)], [line], 2.0))
  // Past the line's end, the distance is to the end point.
  assert_false(@core.polygon_hits_lines([(12.5, 0.0)], [line], 2.0))
  let box : @core.Line = [
    (4.0, -1.0),
    (6.0, -1.0),
    (6.0, 1.0),
    (4.0, 1.0),
    (4.0, -1.0),
  ]
  assert_true(@core.polygon_hits_lines(box, [line], 0.1))
  let point_line : @core.Line = [(1.0, 1.0)]
  assert_true(@core.polygon_hits_lines([(1.5, 1.0)], [point_line], 1.0))
}

///|
test "polygon_hits_point is a containment or a buffered edge" {
  assert_true(@core.polygon_hits_point(square, (5.0, 5.0), 0.0))
  assert_true(@core.polygon_hits_point(square, (11.0, 5.0), 1.5))
  assert_false(@core.polygon_hits_point(square, (12.0, 5.0), 1.5))
  assert_true(@core.polygon_hits_point([(0.0, 0.0)], (0.5, 0.5), 1.0))
}

///|
test "polygon_hits_box finds points, corners and crossing edges" {
  assert_true(@core.polygon_hits_box([(5.0, 5.0)], 0.0, 0.0, 10.0, 10.0))
  assert_false(@core.polygon_hits_box([(15.0, 5.0)], 0.0, 0.0, 10.0, 10.0))
  // The box inside the polygon, and an edge across the box.
  assert_true(@core.polygon_hits_box(square, 2.0, 2.0, 3.0, 3.0))
  let edge : @core.Line = [(-5.0, 5.0), (15.0, 5.0)]
  assert_true(@core.polygon_hits_box(edge, 2.0, 2.0, 8.0, 8.0))
  assert_false(@core.polygon_hits_box(edge, 2.0, 6.0, 8.0, 8.0))
}
