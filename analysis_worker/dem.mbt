///|
/// Elevation grids loaded from DEM tiles, by handle (sharing `next_id` with
/// datasets).
let grids : Map[Int32, @analysis.Grid] = Map([])

///|
/// Largest DEM grid side in cells: 16 tiles of 256 pixels (AGENTS.md §8.2).
const MAX_GRID_SIDE : Int32 = 4096

///|
/// Reads the RGBA input (`width` x `height` pixels of DEM tiles) into a grid of
/// `res_x` x `res_y` m cells; `encoding` 0 Mapbox, 1 Terrarium, 2 GSI, 3 custom
/// (`r`, `g`, `b`, `base`). Returns the grid's handle, or -1 if invalid.
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

///|
/// Writes `Grid::sample` at each input lng, lat pair, the grid being the
/// `tile_size` px tiles of zoom `z` from (`tile_x`, `tile_y`). Returns the
/// count, or -1 for an unknown grid or invalid tiles.
#export_name("grid_sample")
pub fn grid_sample(
  id : Int32,
  z : Int32,
  tile_x : Int32,
  tile_y : Int32,
  tile_size : Int32,
) -> Int32 {
  let coords = @wasmio.input_f64s()
  guard grids.get(id) is Some(g) &&
    z >= 0 &&
    z <= 24 &&
    tile_x >= 0 &&
    tile_y >= 0 &&
    tile_size > 0 &&
    tile_size <= MAX_GRID_SIDE else {
    return -1
  }
  let out = FixedArray::makei(coords.length() / 2, i => {
    let (x, y) = @analysis.mercator_cell(
      trig,
      coords[i * 2],
      coords[i * 2 + 1],
      z,
      tile_x,
      tile_y,
      tile_size,
    )
    g.sample(x, y)
  })
  @wasmio.write_f64s(out)
}

///|
/// Reads `width` x `height` input f64s (rows from the north, NaN for no data) into a
/// grid of `res_x` x `res_y` cells (a GeoTIFF band, npm/src/analysis.ts `loadGrid`).
/// Returns the grid's handle, or -1 if invalid.
#export_name("load_grid")
pub fn load_grid(
  width : Int32,
  height : Int32,
  res_x : Double,
  res_y : Double,
) -> Int32 {
  let values = @wasmio.input_f64s()
  if width <= 0 ||
    height <= 0 ||
    width > MAX_GRID_SIDE ||
    height > MAX_GRID_SIDE ||
    values.length() != width * height ||
    !(res_x > 0.0 && res_y > 0.0) {
    return -1
  }
  let id = next_id.val
  next_id.val += 1
  grids[id] = @analysis.Grid::new(values, width, height, res_x, res_y)
  @wasmio.clear_input()
  id
}

///|
/// Writes `Grid::sample` at each input pair of pixel coordinates (from the grid's
/// north-west corner). Returns the count, or -1 for an unknown grid.
#export_name("grid_sample_pixels")
pub fn grid_sample_pixels(id : Int32) -> Int32 {
  let coords = @wasmio.input_f64s()
  guard grids.get(id) is Some(g) else { return -1 }
  @wasmio.write_f64s(
    FixedArray::makei(coords.length() / 2, i => {
      g.sample(coords[i * 2], coords[i * 2 + 1])
    }),
  )
}
