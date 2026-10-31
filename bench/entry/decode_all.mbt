///|
let geometry : @mvt.Geometry = @mvt.Geometry::new()

///|
let last_properties : Ref[Int32] = Ref(0)

///|
let last_coord_sum : Ref[Double] = Ref(0.0)

///|
const MODE_PROPERTIES = 1

///|
const MODE_GEOMETRY = 2

///|
const MODE_ALL = 3

///|
/// Decodes every feature's properties and geometry, the work a renderer does
/// per tile before tessellation. Returns the point count, or -1 on error.
fn decode_all(bytes : BytesView) -> Int32 {
  decode_parts(bytes, MODE_ALL)
}

///|
/// `decode_all` running only the per-feature steps in `mode`, for the bench breakdown.
fn decode_parts(bytes : BytesView, mode : Int32) -> Int32 {
  let mut points = 0
  let mut props = 0
  let mut sum = 0.0
  let tile = @mvt.Tile::parse(bytes) catch { _ => return -1 }
  for layer in tile.layers {
    for i in 0..<layer.length() {
      if (mode & MODE_PROPERTIES) != 0 {
        props += layer.properties(i).length()
      }
      if (mode & MODE_GEOMETRY) != 0 {
        if !layer.decode_geometry(i, geometry) {
          return -1
        }
        points += geometry.num_points()
        for c in geometry.coords {
          sum += c.to_double()
        }
      }
    }
  }
  last_properties.val = props
  last_coord_sum.val = sum
  points
}

///|
/// Property count of the last successful `decode_*` call.
#export_name("last_properties")
pub fn last_properties_count() -> Int32 {
  last_properties.val
}

///|
/// Sum of all coordinates of the last successful `decode_*` call.
#export_name("last_coord_sum")
pub fn last_coord_sum_value() -> Double {
  last_coord_sum.val
}
