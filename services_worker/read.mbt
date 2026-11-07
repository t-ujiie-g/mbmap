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
/// What the last read gave besides its table: the feature ids and whether the
/// result says `exceededTransferLimit`.
let last_ids : Array[@geom.Prop?] = []

///|
let last_exceeded : Ref[Bool] = Ref(false)

///|
/// Reads the ArcGIS query result placed as input, `pbf` 1 for `f=pbf`, else `f=json`.
/// Returns the length of the `@geom.Table::to_bytes` written at `output_addr`, or
/// minus the length of a UTF-8 error message there (-2 without memory).
#export_name("read_esri")
pub fn read_esri(pbf : Int32) -> Int32 {
  last_ids.clear()
  last_exceeded.val = false
  let input = @wasmio.input_bytes()
  let (table, exceeded) = try {
    if pbf == 1 {
      @formats.read_esri_pbf(input[:])
    } else {
      @formats.read_esri_json(input[:], slow_number=@wasmio.input_number)
    }
  } catch {
    e => return @wasmio.fail_with(e.message())
  }
  last_exceeded.val = exceeded
  if table.ids.iter().any(id => id is Some(_)) {
    last_ids.append(table.ids)
  }
  @wasmio.clear_input()
  @wasmio.write_bytes(table.to_bytes()[:])
}

///|
/// Whether the last read's result said `exceededTransferLimit` (1) or not (0).
#export_name("exceeded")
pub fn exceeded() -> Int32 {
  if last_exceeded.val {
    1
  } else {
    0
  }
}

///|
/// The last read's feature ids at `output_addr`, a property value each (docs/FORMATS.md
/// "Property values"); returns their length, 0 if it had none.
#export_name("ids_out")
pub fn ids_out() -> Int32 {
  if last_ids.is_empty() {
    return 0
  }
  let w = @core.ByteWriter::new()
  for id in last_ids {
    @geom.write_prop(w, id)
  }
  @wasmio.write_bytes(w.to_bytes()[:])
}
