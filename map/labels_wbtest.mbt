///|
/// Two labels laid out as worker/js/symbols.mjs writes them: anchor, text box,
/// feature, size, key, an icon box and its quad, then 3 text layouts (several
/// lines) and 1 (one line).
fn two_labels() -> @render_webgl2.JsBuffer {
  f32_buffer([
    10.0, 20.0, -30.0, -8.0, 30.0, 8.0, 4.0, 12.0, 0.0, -6.0, -6.0, 6.0, 6.0, 1.0,
    0.0, 6.0, 3.0, 6.0, 12.0, 10.0, 20.0, -30.0, -8.0, 30.0, 8.0, 5.0, 12.0, 0.0,
    0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 42.0, 18.0,
  ])
}

///|
test "label columns match the worker's layout" {
  let labels = two_labels()
  assert_eq(length_of(labels), 2 * LABEL_FLOATS)
  assert_eq(f32_at(labels, LABEL_Y), 20.0)
  assert_eq(f32_at(labels, LABEL_BOX + 2), 30.0)
  assert_eq(f32_at(labels, LABEL_FEATURE), 4.0)
  assert_eq(f32_at(labels, LABEL_SIZE), 12.0)
  assert_eq(f32_at(labels, ICON_COLUMN), -6.0)
  assert_eq(f32_at(labels, ICON_LAYOUTS), 1.0)
  assert_eq(f32_at(labels, ICON_COUNT), 6.0)
  assert_eq(f32_at(labels, LABEL_LAYOUTS), 3.0)
  assert_eq(f32_at(labels, LABEL_FIRST), 6.0)
  assert_eq(f32_at(labels, LABEL_FLOATS + LABEL_COUNT), 18.0)
}

///|
test "a multi-line label shows the layout justified to its anchor" {
  let labels = two_labels()
  assert_eq(text_layout(labels, 0, 0.0), 0)
  assert_eq(text_layout(labels, 0, 0.5), 1)
  assert_eq(text_layout(labels, 0, 1.0), 2)
  assert_eq(text_layout(labels, 1, 0.5), 0)
}
