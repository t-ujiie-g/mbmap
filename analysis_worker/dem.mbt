///|
/// Elevation grids loaded from DEM tiles, by handle (sharing `next_id` with
/// datasets).
let grids : Map[Int32, @analysis.Grid] = Map([])

///|
/// Largest DEM grid side in cells: 16 tiles of 256 pixels (AGENTS.md §8.2).
pub const MAX_GRID_SIDE : Int32 = 4096

///|
/// Reads the RGBA input, `width` x `height` pixels of mosaicked DEM tiles, into a
/// new grid of `res_x` x `res_y` m cells. `encoding` is 0 Mapbox, 1 Terrarium,
/// 2 GSI or 3 custom with factors `r`, `g`, `b` and `base`. Returns the grid's
/// handle, or -1 for a bad size or encoding.
#export_name("load_dem")
pub fn load_dem(
  width : Int32,
  height : Int32,
  encoding : Int32,
  r : Double,
  g : Double,
  b : Double,
  base : Double,
  res_x : Double,
  res_y : Double,
) -> Int32 {
  let input = @wasmio.input_bytes()
  if width <= 0 ||
    height <= 0 ||
    width > MAX_GRID_SIDE ||
    height > MAX_GRID_SIDE ||
    input.length() != width * height * 4 ||
    !(res_x > 0.0 && res_y > 0.0) {
    return -1
  }
  let unpack : @raster.Unpack = match encoding {
    0 => @raster.Unpack::mapbox()
    1 => @raster.Unpack::terrarium()
    2 => @raster.Unpack::gsi()
    3 => { r, g, b, base, gsi: false, }
    _ => return -1
  }
  let elev = @raster.elevations(input[:], unpack)
  let id = next_id.val
  next_id.val += 1
  grids[id] = @analysis.Grid::new(elev, width, height, res_x, res_y)
  @wasmio.clear_input()
  id
}

///|
/// Writes a grid's cells as f64s: 0 elevations, 1 slope (degrees), 2 aspect
/// (degrees from north, NaN where flat). Returns the count, or -1 for an unknown
/// grid or kind.
#export_name("grid_values")
pub fn grid_values(id : Int32, kind : Int32) -> Int32 {
  guard grids.get(id) is Some(g) else { return -1 }
  match kind {
    0 => @wasmio.write_f64s(g.elev)
    1 => @wasmio.write_f64s(g.slope(trig))
    2 => @wasmio.write_f64s(g.aspect(trig))
    _ => -1
  }
}

///|
/// Writes a grid's hillshade, a byte per cell (`@analysis.Grid::hillshade`).
/// Returns the count, or -1 for an unknown grid.
#export_name("grid_hillshade")
pub fn grid_hillshade(
  id : Int32,
  azimuth : Double,
  altitude : Double,
  z : Double,
) -> Int32 {
  guard grids.get(id) is Some(g) else { return -1 }
  @wasmio.write_bytes(g.hillshade(trig, azimuth~, altitude~, z~)[:])
}
