///|
test "the atlas packs glyphs in shelves and keeps each glyph's place" {
  let a = @label.Atlas::new(20, 10)
  assert_eq(a.place(1, 8, 4), Some((0, 0)))
  assert_eq(a.place(2, 8, 4), Some((9, 0)))
  // Too wide for the first shelf: a new one below it.
  assert_eq(a.place(3, 8, 3), Some((0, 5)))
  assert_eq(a.place(1, 8, 4), None)
  assert_eq(a.rect(2), Some((9, 0, 8, 4)))
  // A short glyph takes the shortest shelf it fits.
  assert_eq(a.place(4, 2, 2), Some((9, 5)))
  assert_eq(a.place(5, 8, 8), None)
  assert_eq(a.place(6, 0, 3), None)
  assert_eq(a.rect(5), None)
}

///|
test "the grid finds overlapping and touching boxes across cells" {
  let g = @label.Grid::new(200.0, 100.0, cell=32.0)
  assert_false(g.hits(10.0, 10.0, 50.0, 20.0))
  g.insert(10.0, 10.0, 50.0, 20.0)
  assert_true(g.hits(40.0, 15.0, 90.0, 40.0))
  assert_true(g.hits(50.0, 10.0, 60.0, 20.0))
  assert_false(g.hits(50.1, 10.0, 60.0, 20.0))
  assert_false(g.hits(0.0, 30.0, 200.0, 100.0))
  // Boxes reaching past the grid are clamped into its cells.
  g.insert(-50.0, 90.0, 300.0, 140.0)
  assert_true(g.hits(150.0, 95.0, 160.0, 99.0))
  // Off the grid nothing is met; over all of it, everything.
  assert_false(g.hits(201.0, 0.0, 300.0, 100.0))
  assert_true(g.hits(-1.0, -1.0, 201.0, 101.0))
  assert_true(@label.Grid::new(10.0, 10.0).hits(-1.0, -1.0, 11.0, 11.0))
}

///|
test "circles meet boxes and circles as MapLibre's grid has them" {
  let g = @label.Grid::new(200.0, 100.0, cell=32.0)
  g.insert_circle(50.0, 50.0, 10.0)
  // Circles must overlap; a box may touch.
  assert_true(g.hits_circle(65.0, 50.0, 6.0))
  assert_false(g.hits_circle(66.0, 50.0, 6.0))
  assert_true(g.hits(60.0, 40.0, 70.0, 60.0))
  assert_false(g.hits(58.0, 58.0, 70.0, 70.0))
  assert_true(g.hits(57.0, 57.0, 70.0, 70.0))
  g.insert(100.0, 10.0, 120.0, 20.0)
  assert_true(g.hits_circle(125.0, 15.0, 5.0))
  assert_false(g.hits_circle(125.1, 15.0, 5.0))
  assert_false(g.hits_circle(-20.0, 50.0, 10.0))
}

///|
test "a box is inside the grid while some of it lies on it" {
  let g = @label.Grid::new(200.0, 100.0)
  assert_true(g.inside(-10.0, -10.0, 0.0, 0.0))
  assert_false(g.inside(-10.0, -10.0, -0.1, 50.0))
  assert_false(g.inside(200.0, 0.0, 210.0, 10.0))
  assert_true(g.inside(199.9, 99.9, 210.0, 110.0))
}
