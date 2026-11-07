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
/// The networks built so far, by handle.
let networks : Map[Int32, @route.Network] = Map([])

///|
let next_handle : Ref[Int32] = Ref(0)

///|
/// Builds `@route.Network` of the input table's lines and returns its handle,
/// or minus an error's length.
#export_name("network_new")
pub fn network_new(tolerance : Double) -> Int32 {
  let bytes = @wasmio.input_bytes()
  @wasmio.clear_input()
  guard @geom.Table::from_bytes(bytes[:]) is Some(t) else {
    return @wasmio.fail_with("malformed table")
  }
  guard @route.Network::new(t, tolerance~, trig=@wasmio.host_trig()) is Some(n) else {
    return @wasmio.fail_with(
      "no network: NaN coordinates or more than \{@route.MAX_ROUTE_VERTICES} points",
    )
  }
  let handle = next_handle.val
  next_handle.val += 1
  networks[handle] = n
  handle
}

///|
/// Writes the shortest path of network `handle` from (`fx`, `fy`) to (`tx`,
/// `ty`): its weight (km), then x, y pairs; none at all where no path joins
/// them. Returns the f64 count, or minus an error's length.
#export_name("network_path")
pub fn network_path(
  handle : Int32,
  fx : Double,
  fy : Double,
  tx : Double,
  ty : Double,
) -> Int32 {
  guard networks.get(handle) is Some(n) else {
    return @wasmio.fail_with("unknown network")
  }
  match n.find_path(fx, fy, tx, ty) {
    None => @wasmio.write_f64s(FixedArray::make(0, 0.0))
    Some((path, weight)) => {
      let out = FixedArray::make(1 + 2 * path.length(), weight)
      for k, p in path {
        out[1 + 2 * k] = p.0
        out[2 + 2 * k] = p.1
      }
      @wasmio.write_f64s(out)
    }
  }
}

///|
/// Frees network `handle`.
#export_name("network_dispose")
pub fn network_dispose(handle : Int32) -> Unit {
  networks.remove(handle)
}
