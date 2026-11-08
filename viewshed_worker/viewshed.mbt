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
/// `@viewshed.viewshed` of the input's `width` x `height` f64 elevations: the
/// arguments and output as docs/FORMATS.md "Analysis worker messages" `viewshed`
/// lists them (`mode` 0 normal, 1 DEM, 2 ground; `semi_major` NaN for none).
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
) -> Int32 {
  guard @viewshed.grid_fits(width, height) &&
    @wasmio.input_length() == width * height * 8 else {
    @wasmio.clear_input()
    return @wasmio.fail_with(no_viewshed)
  }
  let values = @wasmio.input_f64s()
  @wasmio.clear_input()
  let options = @viewshed.ViewshedOptions::new(
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
  guard @viewshed.viewshed(
      values,
      width,
      height,
      [g0, g1, g2, g3, g4, g5],
      None,
      options,
      trig=@wasmio.host_trig(),
    )
    is Some(r) else {
    return @wasmio.fail_with(no_viewshed)
  }
  let out = FixedArray::make(8 + r.values.length(), 0.0)
  out[0] = r.width.to_double()
  out[1] = r.height.to_double()
  for k in 0..<6 {
    out[2 + k] = r.geotransform[k]
  }
  for k in 0..<r.values.length() {
    out[8 + k] = r.values[k]
  }
  @wasmio.write_f64s(out)
}

///|
let no_viewshed = "no viewshed: check the observer, the distances and the grid (at most \{@viewshed.MAX_VIEWSHED_CELLS} cells)"
