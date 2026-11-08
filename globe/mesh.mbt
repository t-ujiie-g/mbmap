// MapLibre GL JS 6.16.0's globe tile meshes (src/util/create_tile_mesh.ts and the globe's granularity),
// BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.

///|
/// The y of a vertex at the north pole (MapLibre's `NORTH_POLE_Y`): globe shaders
/// put it on the pole.
pub const NORTH_POLE_Y : Int32 = -32768

///|
/// The y of a vertex at the south pole (`SOUTH_POLE_Y`).
pub const SOUTH_POLE_Y : Int32 = 32767

///|
/// Quads per tile edge of a raster or background tile at zoom `z` on the globe:
/// 128 at zoom 0, halving to at least 32 (the globe's `tile` granularity).
pub fn tile_granularity(z : Int32) -> Int32 {
  let divisor = 1 << @cmp.minimum(z, 30)
  @cmp.maximum(@cmp.maximum(128 / divisor, 32), 1)
}

///|
/// A tile's grid of `granularity` quads per edge (`createTileMesh`): x, y pairs in
/// tile units and triangle indices; `borders` adds a ring of quads just outside,
/// `north` and `south` a row reaching the pole.
pub fn tile_mesh(
  granularity : Int32,
  borders~ : Bool = false,
  north~ : Bool = false,
  south~ : Bool = false,
) -> (FixedArray[Int32], FixedArray[Int32]) {
  let g = @cmp.maximum(granularity, 1)
  let extent = @core.TILE_EXTENT
  let border = extent / 128
  let quads_x = g + (if borders { 2 } else { 0 })
  let quads_y = g +
    (if north || borders { 1 } else { 0 }) +
    (if south || borders { 1 } else { 0 })
  let per_x = quads_x + 1
  let x0 = if borders { -1 } else { 0 }
  let y0 = if borders || north { -1 } else { 0 }
  let x1 = g + (if borders { 1 } else { 0 })
  let y1 = g + (if borders || south { 1 } else { 0 })
  let vertices = FixedArray::make(per_x * (quads_y + 1) * 2, 0)
  let mut v = 0
  for y in y0..<=y1 {
    for x in x0..<=x1 {
      let vx = if x == -1 {
        -border
      } else if x == g + 1 {
        extent + border
      } else {
        (x.to_double() / g.to_double() * extent.to_double()).to_int()
      }
      let vy = if y == -1 {
        if north {
          NORTH_POLE_Y
        } else {
          -border
        }
      } else if y == g + 1 {
        if south {
          SOUTH_POLE_Y
        } else {
          extent + border
        }
      } else {
        (y.to_double() / g.to_double() * extent.to_double()).to_int()
      }
      vertices[v] = vx
      vertices[v + 1] = vy
      v += 2
    }
  }
  let indices = FixedArray::make(quads_x * quads_y * 6, 0)
  let mut i = 0
  for y in 0..<quads_y {
    for x in 0..<quads_x {
      let v0 = x + y * per_x
      let v1 = x + 1 + y * per_x
      let v2 = x + (y + 1) * per_x
      let v3 = x + 1 + (y + 1) * per_x
      indices[i] = v0
      indices[i + 1] = v2
      indices[i + 2] = v1
      indices[i + 3] = v1
      indices[i + 4] = v2
      indices[i + 5] = v3
      i += 6
    }
  }
  (vertices, indices)
}
