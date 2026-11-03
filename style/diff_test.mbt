///|
fn diff_style(source : String, layer : String) -> @style.Style raise {
  @style.Style::parse(
    "{\"version\": 8, \"sources\": {\"s\": \{source}}, \"layers\": [\{layer}]}",
  )
}

///|
let base_source : String = "{\"type\": \"vector\", \"tiles\": [\"https://x/{z}/{x}/{y}.pbf\"], \"maxzoom\": 14}"

///|
let base_layer : String = "{\"id\": \"road\", \"type\": \"line\", \"source\": \"s\", \"source-layer\": \"road\", \"paint\": {\"line-color\": \"#fff\", \"line-width\": 2}}"

///|
test "same_tiles holds across paint constants and fails on what workers build" {
  let a = diff_style(base_source, base_layer).layers[0]
  let painted = diff_style(
      base_source, "{\"id\": \"road\", \"type\": \"line\", \"source\": \"s\", \"source-layer\": \"road\", \"paint\": {\"line-color\": \"#f00\", \"line-width\": 5, \"line-opacity\": 0.5}}",
    ).layers[0]
  assert_true(a.same_tiles(painted))
  for
    other in [
      "{\"id\": \"road2\", \"type\": \"line\", \"source\": \"s\", \"source-layer\": \"road\"}",
      "{\"id\": \"road\", \"type\": \"line\", \"source\": \"s\", \"source-layer\": \"rail\"}",
      "{\"id\": \"road\", \"type\": \"line\", \"source\": \"s\", \"source-layer\": \"road\", \"minzoom\": 10}",
      "{\"id\": \"road\", \"type\": \"line\", \"source\": \"s\", \"source-layer\": \"road\", \"filter\": [\"==\", [\"get\", \"k\"], 1]}",
      "{\"id\": \"road\", \"type\": \"line\", \"source\": \"s\", \"source-layer\": \"road\", \"layout\": {\"line-cap\": \"round\"}}",
      "{\"id\": \"road\", \"type\": \"line\", \"source\": \"s\", \"source-layer\": \"road\", \"paint\": {\"line-width\": [\"get\", \"w\"]}}",
      "{\"id\": \"road\", \"type\": \"fill\", \"source\": \"s\", \"source-layer\": \"road\"}",
    ] {
    assert_false(a.same_tiles(diff_style(base_source, other).layers[0]))
  }
}

///|
test "same_tiles fails when per-vertex paint changes, even with the same inputs" {
  let widths = (w : String) => {
    diff_style(
      base_source,
      "{\"id\": \"road\", \"type\": \"line\", \"source\": \"s\", \"source-layer\": \"road\", \"paint\": {\"line-width\": [\"match\", [\"get\", \"k\"], 1, \{w}, 2]}}",
    ).layers[0]
  }
  assert_true(widths("4").same_tiles(widths("4")))
  assert_false(widths("4").same_tiles(widths("6")))
}

///|
test "Source::same compares what tiles are fetched and cut with" {
  let a = diff_style(base_source, base_layer).sources[0]
  let attributed = diff_style(
      "{\"type\": \"vector\", \"tiles\": [\"https://x/{z}/{x}/{y}.pbf\"], \"maxzoom\": 14, \"attribution\": \"x\"}",
      base_layer,
    ).sources[0]
  assert_true(a.same(attributed))
  for
    other in [
      "{\"type\": \"vector\", \"tiles\": [\"https://y/{z}/{x}/{y}.pbf\"], \"maxzoom\": 14}",
      "{\"type\": \"vector\", \"tiles\": [\"https://x/{z}/{x}/{y}.pbf\"], \"maxzoom\": 15}",
      "{\"type\": \"vector\", \"tiles\": [\"https://x/{z}/{x}/{y}.pbf\"], \"minzoom\": 2, \"maxzoom\": 14}",
    ] {
    assert_false(a.same(diff_style(other, base_layer).sources[0]))
  }
}
