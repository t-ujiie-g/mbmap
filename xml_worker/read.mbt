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
/// The last read table's feature ids, empty if it had none.
let last_ids : Array[@geom.Prop?] = []

///|
/// The table in `@geom.Table::to_bytes` form at `output_addr`: its length, or
/// minus the length of the UTF-8 error message written there instead.
fn table_out(table : @geom.Table) -> Int32 {
  @wasmio.clear_input()
  if table.ids.iter().any(id => id is Some(_)) {
    last_ids.append(table.ids)
  }
  @wasmio.write_bytes(table.to_bytes()[:])
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

///|
/// Reads the KML placed as input (docs/FORMATS.md "Data worker messages"), as
/// `table_out` returns.
#export_name("read_kml")
pub fn read_kml() -> Int32 {
  last_ids.clear()
  let table = @kml.read_kml(
    @wasmio.input_bytes(),
    number=@wasmio.host_text_to_number,
    number_text=@wasmio.host_number_to_text,
    trig=@wasmio.host_trig(),
  ) catch {
    e => return @wasmio.fail_with(e.message())
  }
  table_out(table)
}

///|
/// Reads the GPX placed as input, as `table_out` returns.
#export_name("read_gpx")
pub fn read_gpx() -> Int32 {
  last_ids.clear()
  let table = @kml.read_gpx(
    @wasmio.input_bytes(),
    number=@wasmio.host_text_to_number,
    number_text=@wasmio.host_number_to_text,
  ) catch {
    e => return @wasmio.fail_with(e.message())
  }
  table_out(table)
}
