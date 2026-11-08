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
/// What the last read gave besides its table: each row's SRID, the names of the
/// input's layers, the table's feature ids.
let last_srids : Array[Int32] = []

///|
let last_layers : Array[String] = []

///|
let last_ids : Array[@geom.Prop?] = []

///|
/// Writes `table` in `@geom.Table::to_bytes` form at `output_addr`; returns its
/// length (-2 without memory).
fn table_out(table : @geom.Table) -> Int32 {
  @wasmio.clear_input()
  last_ids.clear()
  if table.ids.iter().any(id => id is Some(_)) {
    last_ids.append(table.ids)
  }
  @wasmio.write_table(table)
}

///|
/// Starts a read: forgets what the last one gave.
fn begin() -> Array[Int32] {
  last_srids.clear()
  last_layers.clear()
  last_ids.clear()
  last_srids
}

///|
/// The last read's row SRIDs as i32s at `output_addr`; returns their count, 0 if
/// no row had one.
#export_name("srids_out")
pub fn srids_out() -> Int32 {
  if last_srids.iter().all(s => s == 0) {
    return 0
  }
  @wasmio.write_i32s(last_srids[:])
}

///|
/// The last read's layer names at `output_addr`, each a u32 length and UTF-8;
/// returns their length.
#export_name("layers_out")
pub fn layers_out() -> Int32 {
  let w = @core.ByteWriter::new()
  for name in last_layers {
    w.utf8(name)
  }
  @wasmio.write_bytes(w.to_bytes()[:])
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
fn host_decode(addr : Int32, len : Int32) -> Int32 = "host" "decode"

///|
fn host_text_code(i : Int32) -> Int32 = "host" "text_code"

///|
/// The host's text of input bytes `start..<end`, decoded in the encoding it was
/// told (data_worker/js/read.mjs `dbfText`).
fn input_text(start : Int32, end : Int32) -> String {
  let n = host_decode(@wasmio.PAGE + start, end - start)
  let sb = StringBuilder()
  for i in 0..<n {
    sb.write_char(host_text_code(i).unsafe_to_char())
  }
  sb.to_string()
}

///|
/// The three NUL-ended column names in the first `names` bytes of `input`, None
/// for another count or bytes after the last.
fn column_names(input : BytesView, names : Int32) -> Array[String]? {
  let given = []
  let mut start = 0
  for i in 0..<names {
    if input[i] == b'\x00' {
      given.push(@core.utf8_lossy(input[start:i]))
      start = i + 1
    }
  }
  if given.length() == 3 && start == names {
    Some(given)
  } else {
    None
  }
}

///|
/// Reads the CSV placed as input after `names` bytes of column names, as
/// docs/FORMATS.md "Data worker messages" has it. Returns the length of the table
/// written, or minus the length of a UTF-8 error message at `output_addr`.
#export_name("read_csv")
pub fn read_csv(
  names : Int32,
  delimiter : Int32,
  header : Int32,
  typing : Int32,
) -> Int32 {
  let input = @wasmio.input_bytes()
  guard names >= 0 && names <= input.length() else {
    return @wasmio.fail_with("invalid column names")
  }
  guard column_names(input, names) is Some(given) else {
    return @wasmio.fail_with("invalid column names")
  }
  let given = given.map(n => if n == "" { None } else { Some(n) })
  let options = @formats.CsvOptions::new(
    delimiter~,
    header=header == 1,
    dynamic_typing=typing == 1,
    latitude?=given[0],
    longitude?=given[1],
    geometry?=given[2],
  )
  let table = @formats.read_csv(
    input[names:],
    options,
    slow_number=(s, e) => @wasmio.input_number(names + s, names + e),
    srids=begin(),
  ) catch {
    e => return @wasmio.fail_with(e.message())
  }
  table_out(table)
}

///|
/// Reads the WKT or EWKT placed as input (geometries one after another), as
/// `read_csv` returns.
#export_name("read_wkt")
pub fn read_wkt() -> Int32 {
  let table = @formats.read_wkt(
    @wasmio.input_bytes()[:],
    slow_number=@wasmio.input_number,
    srids=begin(),
  ) catch {
    e => return @wasmio.fail_with(e.message())
  }
  table_out(table)
}

///|
/// Reads the WKB or EWKB placed as input (`@formats.read_wkb_any`), as `read_csv`
/// returns.
#export_name("read_wkb")
pub fn read_wkb() -> Int32 {
  let input = @wasmio.input_bytes()
  let srids = begin()
  let table = @formats.read_wkb_any(input[:], srids~) catch {
    e => return @wasmio.fail_with(e.message())
  }
  table_out(table)
}

///|
/// Reads the shapefile placed as input: `shp` bytes of .shp, then `dbf` bytes of
/// .dbf (0 for none), the .dbf's text decoded by the host; returns as `read_csv`.
#export_name("read_shapefile")
pub fn read_shapefile(shp : Int32, dbf : Int32) -> Int32 {
  let input = @wasmio.input_bytes()
  guard shp >= 0 && dbf >= 0 && shp + dbf == input.length() else {
    return @wasmio.fail_with("invalid lengths")
  }
  begin() |> ignore
  let table = @formats.read_shapefile(
    input[:shp],
    if dbf > 0 {
      Some(input[shp:])
    } else {
      None
    },
    text=(s, e) => input_text(shp + s, shp + e),
    slow_number=(s, e) => @wasmio.input_number(shp + s, shp + e),
  ) catch {
    e => return @wasmio.fail_with(e.message())
  }
  table_out(table)
}

///|
/// Reads the TopoJSON placed as input after `name` bytes naming the object to read
/// (UTF-8; -1 for the first); returns as `read_csv`, the object names kept for
/// `layers_out` and the ids for `ids_out`.
#export_name("read_topojson")
pub fn read_topojson(name : Int32) -> Int32 {
  let input = @wasmio.input_bytes()
  guard name >= -1 && name <= input.length() else {
    return @wasmio.fail_with("invalid object name")
  }
  begin() |> ignore
  let skip = @cmp.maximum(name, 0)
  let (table, names) = @formats.read_topojson(
    input[skip:],
    if name >= 0 {
      Some(@core.utf8_lossy(input[:name]))
    } else {
      None
    },
    slow_number=(s, e) => @wasmio.input_number(skip + s, skip + e),
  ) catch {
    e => return @wasmio.fail_with(e.message())
  }
  last_layers.append(names)
  table_out(table)
}

///|
/// Reads the FlatGeobuf placed as input, then `ids` u32 feature indices (-1 for
/// none: the whole file); returns as `read_csv`, the ids kept for `ids_out`.
#export_name("read_flatgeobuf")
pub fn read_flatgeobuf(ids : Int32) -> Int32 {
  let input = @wasmio.input_bytes()
  let end = input.length() - @cmp.maximum(ids, 0) * 4
  guard ids >= -1 && ids <= input.length() / 4 && end >= 0 else {
    return @wasmio.fail_with("invalid ids")
  }
  begin() |> ignore
  let given = if ids < 0 {
    None
  } else {
    let r = @core.ByteReader::new(input[end:])
    Some(Array::makei(ids, _ => r.u32()))
  }
  let table = @formats.read_flatgeobuf(input[:end], ids?=given) catch {
    e => return @wasmio.fail_with(e.message())
  }
  table_out(table)
}

///|
/// Reads the GeoJSON placed as input (collections flattened); returns as `read_csv`,
/// the feature ids kept for `ids_out`.
#export_name("read_geojson")
pub fn read_geojson() -> Int32 {
  begin() |> ignore
  let table = @formats.read_geojson(
    @wasmio.input_bytes()[:],
    slow_number=@wasmio.input_number,
  ) catch {
    e => return @wasmio.fail_with(e.message())
  }
  table_out(table)
}

///|
/// Writes as CSV the table placed after `names` bytes of three NUL-ended column names
/// (WKT, longitude, latitude); `mode` 0 no geometry, 1 WKT, 2 coordinates, 3 2 for
/// points, else 1, 0 without geometry. Returns the UTF-8's length, or minus an error's.
#export_name("write_csv")
pub fn write_csv(
  names : Int32,
  delimiter : Int32,
  header : Int32,
  mode : Int32,
) -> Int32 {
  let input = @wasmio.input_bytes()
  guard names >= 0 &&
    names <= input.length() &&
    delimiter > 0 &&
    delimiter < 128 &&
    mode >= 0 &&
    mode <= 3 else {
    return @wasmio.fail_with("invalid arguments")
  }
  guard column_names(input, names) is Some(given) else {
    return @wasmio.fail_with("invalid column names")
  }
  guard @wasmio.input_table(names, input.length() - names) is Some(table) else {
    return @wasmio.fail_with("invalid table")
  }
  let mut mode = mode
  if mode == 3 {
    mode = 0
    for k in table.kinds {
      match k {
        NoGeometry => ()
        Point => mode = @cmp.maximum(mode, 2)
        _ => mode = 1
      }
      if mode == 1 {
        break
      }
    }
  }
  let geometry : @formats.CsvGeometry = match mode {
    1 => Wkt(given[0])
    2 => LonLat(given[1], given[2])
    _ => Omitted
  }
  let text = @formats.write_csv(
    table,
    delimiter=delimiter.unsafe_to_char(),
    header=header == 1,
    geometry~,
    number_text=@wasmio.host_number_to_text,
  ) catch {
    Invalid(m, ..) => return @wasmio.fail_with(m)
  }
  @wasmio.clear_input()
  @wasmio.write_bytes(@utf8.encode(text)[:])
}
