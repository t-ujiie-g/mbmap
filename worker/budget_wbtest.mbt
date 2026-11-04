///|
test "a layer's budget refuses features past MAX_PACKED_BYTES before and after tessellating" {
  let p = TileProcessor::new(@style.Style::parse("{\"layers\": []}"))
  p.budget = MAX_PACKED_BYTES.to_double()
  assert_true(
    p.may_fit(MAX_PACKED_BYTES / FILL_VERTEX_BYTES, FILL_VERTEX_BYTES),
  )
  assert_eq(p.error, "")
  assert_false(
    p.may_fit(MAX_PACKED_BYTES / LINE_VERTEX_BYTES + 1, LINE_VERTEX_BYTES),
  )
  assert_true(p.error.contains("exceeds"))
  p.error = ""
  assert_true(p.spend(1000, LINE_VERTEX_BYTES, 3000))
  assert_eq(p.budget, MAX_PACKED_BYTES.to_double() - 14000.0)
  assert_false(p.spend(0x7fffffff, EXTRUSION_VERTEX_BYTES, 0))
  assert_true(p.error.contains("exceeds"))
}
