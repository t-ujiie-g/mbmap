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
/// Writes `table` in `@geom.Table::to_bytes` form at `output_addr`; returns its
/// length (-2 without memory).
fn table_out(table : @geom.Table) -> Int32 {
  @wasmio.write_bytes(table.to_bytes()[:])
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
  let given : Array[String?] = []
  let mut start = 0
  for i in 0..<names {
    if input[i] == b'\x00' {
      given.push(
        if i > start {
          Some(@core.utf8_lossy(input[start:i]))
        } else {
          None
        },
      )
      start = i + 1
    }
  }
  guard given.length() == 3 && start == names else {
    return @wasmio.fail_with("invalid column names")
  }
  let options = @formats.CsvOptions::new(
    delimiter~,
    header=header == 1,
    dynamic_typing=typing == 1,
    latitude?=given[0],
    longitude?=given[1],
    geometry?=given[2],
  )
  let table = @formats.read_csv(input[names:], options, slow_number=(s, e) => {
    @wasmio.input_number(names + s, names + e)
  }) catch {
    e => return @wasmio.fail_with(e.message())
  }
  @wasmio.clear_input()
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
  ) catch {
    e => return @wasmio.fail_with(e.message())
  }
  @wasmio.clear_input()
  table_out(table)
}

///|
/// Reads the WKB or EWKB placed as input (geometries one after another), binary
/// or as hexadecimal text (told apart by the first byte: binary WKB starts with
/// its byte order, 0 or 1), as `read_csv` returns.
#export_name("read_wkb")
pub fn read_wkb() -> Int32 {
  let input = @wasmio.input_bytes()
  let mut first = 0
  while first < input.length() &&
        (
          input[first] == b' ' ||
          input[first] == b'\t' ||
          input[first] == b'\n' ||
          input[first] == b'\r'
        ) {
    first += 1
  }
  let binary = first == input.length() ||
    input[first] == b'\x00' ||
    input[first] == b'\x01'
  let table = try {
    if binary {
      @formats.read_wkb(input[:])
    } else {
      @formats.read_wkb_hex(input[:])
    }
  } catch {
    e => return @wasmio.fail_with(e.message())
  }
  @wasmio.clear_input()
  table_out(table)
}
