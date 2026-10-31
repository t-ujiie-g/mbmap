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
test "the grid finds overlapping boxes across cells, not touching ones" {
  let g = @label.Grid::new(200.0, 100.0, cell=32.0)
  assert_false(g.hits(10.0, 10.0, 50.0, 20.0))
  g.insert(10.0, 10.0, 50.0, 20.0)
  assert_true(g.hits(40.0, 15.0, 90.0, 40.0))
  assert_false(g.hits(50.0, 10.0, 60.0, 20.0))
  assert_false(g.hits(0.0, 30.0, 200.0, 100.0))
  // Boxes reaching past the viewport are clamped into its cells.
  g.insert(-50.0, 90.0, 300.0, 140.0)
  assert_true(g.hits(150.0, 95.0, 160.0, 99.0))
}
