///|
/// The host's `Math.sin` and `Math.log`: projections then match geojson-vt
/// bit for bit (see `@tiler.Trig`). js/worker.mjs passes `{ Math }`.
fn host_sin(x : Double) -> Double = "Math" "sin"

///|
fn host_log(x : Double) -> Double = "Math" "log"

///|
/// The JSON number at `[addr, addr + len)` of linear memory, by the host's
/// `Number()`: correctly rounded like strconv, which it keeps out of the module.
fn host_number(addr : Int32, len : Int32) -> Double = "host" "number"

///|
/// Turns MapLibre's GeoJSON source options, in pixels, into tile units.
let units_per_pixel : Double = @core.TILE_EXTENT.to_double() / @core.TILE_SIZE

///|
/// Each loaded source's table and tiler, by its index in the style.
let sources : Map[Int32, (@geom.Table, @tiler.Tiler)] = Map([])

///|
/// Reads the GeoJSON placed as input as source `source`, with its style
/// options (`buffer` and `tolerance` in pixels). Returns the feature count,
/// or minus the length of a UTF-8 error message at `output_addr`.
#export_name("load")
pub fn load(
  source : Int32,
  max_zoom : Int32,
  buffer : Double,
  tolerance : Double,
) -> Int32 {
  let table = @formats.read_geojson(input_bytes()[:], slow_number=(s, e) => {
    host_number(PAGE + s, e - s)
  }) catch {
    e => return -write_output(@utf8.encode(e.message()))
  }
  let options : @tiler.TilerOptions = {
    ..@tiler.TilerOptions::default(),
    max_zoom,
    buffer: (buffer * units_per_pixel).round().to_int(),
    tolerance: tolerance * units_per_pixel,
  }
  let trig : @tiler.Trig = { sin: host_sin, ln: host_log, }
  sources[source] = (table, @tiler.Tiler::new(table, options~, trig~))
  table.length()
}

///|
/// Cuts tile (z, x, y) of source `source` and writes it, encoded, at
/// `output_addr`. Returns its length, 0 if the source has no features
/// there, or -1 if the source is not loaded or memory ran out.
#export_name("tile")
pub fn tile(source : Int32, z : Int32, x : Int32, y : Int32) -> Int32 {
  guard sources.get(source) is Some((table, tiler)) else { return -1 }
  input_len.val = 0
  match tiler.tile(z, x, y) {
    None => 0
    Some(d) if d.types.is_empty() => 0
    Some(d) => write_output(@tiler.encode_tile(d, table))
  }
}
