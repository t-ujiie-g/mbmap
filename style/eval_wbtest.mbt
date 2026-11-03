///|
test "reads_line_progress and reads_heatmap_density find their operator at any depth" {
  let progress = compile(
    @json.parse(
      "[\"interpolate\", [\"linear\"], [\"line-progress\"], 0, \"#000000\", 1, \"#ffffff\"]",
    ),
  )
  let density = compile(
    @json.parse("[\"case\", [\">\", [\"heatmap-density\"], 0.5], 1, 0]"),
  )
  let neither = compile(@json.parse("[\"+\", [\"zoom\"], [\"get\", \"x\"]]"))
  assert_eq(
    (progress.reads_line_progress(), progress.reads_heatmap_density()),
    (true, false),
  )
  assert_eq(
    (density.reads_line_progress(), density.reads_heatmap_density()),
    (false, true),
  )
  assert_eq(
    (neither.reads_line_progress(), neither.reads_heatmap_density()),
    (false, false),
  )
}
