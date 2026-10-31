///|
/// The host's `Math.sin` and `Math.log`: projections then match geojson-vt
/// bit for bit (see `@tiler.Trig`). js/worker.mjs passes `{ Math }`.
fn host_sin(x : Double) -> Double = "Math" "sin"

///|
fn host_log(x : Double) -> Double = "Math" "log"

///|
/// Tile units per pixel of a 512 px tile, to turn MapLibre's GeoJSON source
/// options (in pixels) into tiler options.
const UNITS_PER_PIXEL : Double = 8.0

///|
/// Each loaded source's table and tiler, by its index in the style.
let sources : Map[Int32, (@geom.Table, @tiler.Tiler)] = Map([])

///|
/// Reads the GeoJSON placed as input as source `source`, with its style
/// options (`max_zoom`, and `buffer` and `tolerance` in pixels of a 512 px
/// tile). Returns the feature count, or minus the length of a UTF-8 error
/// message at `output_addr`.
#export_name("load")
pub fn load(
  source : Int32,
  max_zoom : Int32,
  buffer : Double,
  tolerance : Double,
) -> Int32 {
  let table = @formats.read_geojson(input_bytes()[:]) catch {
    e => return -write_output(@utf8.encode(e.message()))
  }
  let options : @tiler.TilerOptions = {
    ..@tiler.TilerOptions::default(),
    max_zoom,
    buffer: (buffer * UNITS_PER_PIXEL).round().to_int(),
    tolerance: tolerance * UNITS_PER_PIXEL,
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
