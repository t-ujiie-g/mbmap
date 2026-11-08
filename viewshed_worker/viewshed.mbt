///|
/// Makes room for `len` input bytes and returns where JS should write them,
/// or -1 if `len` is too large.
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  @wasmio.prepare_input(len, @wasmio.MAX_INPUT_BYTES)
}

///|
/// Where the last call's output starts.
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  @wasmio.output_addr()
}

///|
/// `@viewshed.ViewshedOptions` from the exports' arguments.
fn options_of(
  ox : Double,
  oy : Double,
  observer_height : Double,
  target_height : Double,
  max_distance : Double,
  curvature_coeff : Double,
  semi_major : Double,
  mode : Int32,
  visible : Double,
  invisible : Double,
  out_of_range : Double,
) -> @viewshed.ViewshedOptions {
  @viewshed.ViewshedOptions::new(
    ox,
    oy,
    observer_height~,
    target_height~,
    max_distance~,
    curvature_coeff~,
    semi_major?=if semi_major.is_nan() { None } else { Some(semi_major) },
    visible_value=visible,
    invisible_value=invisible,
    out_of_range_value=out_of_range,
    mode=match mode {
      1 => Dem
      2 => Ground
      _ => Normal
    },
  )
}

///|
/// Writes `@viewshed.viewshed_window` (x, y, width, height as i32s) for
/// `viewshed`'s arguments and returns 4, or minus an error's length.
#export_name("viewshed_window")
pub fn viewshed_window(
  width : Int32,
  height : Int32,
  g0 : Double,
  g1 : Double,
  g2 : Double,
  g3 : Double,
  g4 : Double,
  g5 : Double,
  ox : Double,
  oy : Double,
  observer_height : Double,
  target_height : Double,
  max_distance : Double,
  curvature_coeff : Double,
  semi_major : Double,
  mode : Int32,
  visible : Double,
  invisible : Double,
  out_of_range : Double,
) -> Int32 {
  @wasmio.clear_input()
  let options = options_of(
    ox, oy, observer_height, target_height, max_distance, curvature_coeff, semi_major,
    mode, visible, invisible, out_of_range,
  )
  guard @viewshed.viewshed_window(
      width,
      height,
      [g0, g1, g2, g3, g4, g5],
      options,
      trig=@wasmio.host_trig(),
    )
    is Some((x, y, w, h)) else {
    return @wasmio.fail_with(no_viewshed)
  }
  @wasmio.write_i32s([x, y, w, h][:])
}

///|
/// `@viewshed.viewshed` of the input's f64 elevations: the arguments and output
/// as docs/FORMATS.md "Analysis worker messages" `viewshed` lists them (`mode` 0
/// normal, 1 DEM, 2 ground; `semi_major` NaN for none). The input holds the
/// `cw` x `ch` cells from (`cx`, `cy`) of the `width` x `height` grid, which
/// must take in `viewshed_window`'s; `cw` 0 for the whole grid.
#export_name("viewshed")
pub fn viewshed(
  width : Int32,
  height : Int32,
  g0 : Double,
  g1 : Double,
  g2 : Double,
  g3 : Double,
  g4 : Double,
  g5 : Double,
  ox : Double,
  oy : Double,
  observer_height : Double,
  target_height : Double,
  max_distance : Double,
  curvature_coeff : Double,
  semi_major : Double,
  mode : Int32,
  visible : Double,
  invisible : Double,
  out_of_range : Double,
  cx : Int32,
  cy : Int32,
  cw : Int32,
  ch : Int32,
) -> Int32 {
  let cells = if cw == 0 { (0, 0, width, height) } else { (cx, cy, cw, ch) }
  guard @viewshed.grid_fits(width, height) &&
    @viewshed.grid_fits(cells.2, cells.3) &&
    @wasmio.input_length() == cells.2 * cells.3 * 8 else {
    @wasmio.clear_input()
    return @wasmio.fail_with(no_viewshed)
  }
  let values = @wasmio.input_f64s()
  @wasmio.clear_input()
  let options = options_of(
    ox, oy, observer_height, target_height, max_distance, curvature_coeff, semi_major,
    mode, visible, invisible, out_of_range,
  )
  guard @viewshed.viewshed(
      values,
      width,
      height,
      [g0, g1, g2, g3, g4, g5],
      None,
      options,
      trig=@wasmio.host_trig(),
      cells~,
    )
    is Some(r) else {
    return @wasmio.fail_with(no_viewshed)
  }
  let head = FixedArray::make(8, 0.0)
  head[0] = r.width.to_double()
  head[1] = r.height.to_double()
  for k in 0..<6 {
    head[2 + k] = r.geotransform[k]
  }
  @wasmio.write_f64s_after(head, r.values)
}

///|
let no_viewshed = "no viewshed: check the observer, the distances and the grid (at most \{@viewshed.MAX_VIEWSHED_CELLS} cells)"
