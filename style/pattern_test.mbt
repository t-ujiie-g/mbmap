///|
fn pattern_layer(kind : String, paint : String) -> @style.StyleLayer raise {
  @style.Style::parse(
    "{\"layers\": [{\"id\": \"a\", \"type\": \"\{kind}\", \"paint\": \{paint}}]}",
  ).layers[0]
}

///|
test "patterns are read for fills, backgrounds, lines and extrusions" {
  let at = (l : @style.StyleLayer, z : Double) => {
    l.pattern.unwrap().eval(z, @style.NoFeature::{ })
  }
  assert_eq(
    at(pattern_layer("fill", "{\"fill-pattern\": \"dots\"}"), 14),
    Str("dots"),
  )
  assert_eq(
    at(
      pattern_layer(
        "background", "{\"background-pattern\": [\"image\", \"grid\"]}",
      ),
      14,
    ),
    Str("grid"),
  )
  let stepped = pattern_layer(
    "fill", "{\"fill-pattern\": [\"step\", [\"zoom\"], \"a\", 15, \"b\"]}",
  )
  assert_eq((at(stepped, 14), at(stepped, 15)), (Str("a"), Str("b")))
  assert_true(pattern_layer("circle", "{}").pattern is None)
  let line = pattern_layer("line", "{\"line-pattern\": \"dots\"}")
  assert_eq(at(line, 14), Str("dots"))
  assert_true(line.line_distances())
  assert_false(pattern_layer("line", "{}").line_distances())
  assert_true(
    pattern_layer("fill-extrusion", "{\"fill-extrusion-pattern\": \"x\"}").pattern
    is Some(_),
  )
}

///|
test "a pattern picked by feature draws the layer by groups, not per vertex" {
  let by_feature = pattern_layer(
    "fill", "{\"fill-pattern\": [\"get\", \"p\"], \"fill-opacity\": [\"get\", \"o\"]}",
  )
  assert_true(by_feature.paints_by_group())
  assert_eq(by_feature.vertex_paint().length(), 0)
  let constant = pattern_layer(
    "fill", "{\"fill-pattern\": \"dots\", \"fill-opacity\": [\"get\", \"o\"]}",
  )
  assert_false(constant.paints_by_group())
  assert_eq(constant.vertex_paint().length(), 1)
  assert_false(by_feature.same_tiles(constant))
}
