// Ported from @maplibre/geojson-vt 6.3.0: MIT License, Copyright (c) 2025
// MapLibre contributors, and ISC License, Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// One tile's features in tile units, laid out as docs/FORMATS.md's "Columnar
/// tile" (`rows` are their table rows). Exteriors wind clockwise with y down and
/// holes counterclockwise, as MVT wants. With line metrics, `clips` holds each
/// feature's start and end along its line (shares of its length; NaN if none).
pub struct TileData {
  types : Array[Int32]
  rows : Array[Int32]
  ring_ends : Array[Int32]
  point_ends : Array[Int32]
  xy : Array[Int32]
  clips : Array[Double]
}

///|
/// A tile of the index: its features before transformation (world
/// coordinates), what they came from (kept for drilling down later) and the
/// counts the index splits on.
priv struct Tile {
  z : Int32
  x : Int32
  y : Int32
  mut source : Array[FRef]?
  mut min_x : Double
  mut min_y : Double
  mut max_x : Double
  mut max_y : Double
  mut num_points : Int32
  types : Array[Int32]
  rows : Array[Int32]
  ring_ends : Array[Int32]
  point_ends : Array[Int32]
  coords : Array[Double]
  clips : Array[Double]
  mut data : TileData?
}

///|
/// geojson-vt's `createTile`: the features of `set` simplified for zoom `z`.
fn create_tile(
  set : Array[FRef],
  z : Int32,
  x : Int32,
  y : Int32,
  options : TilerOptions,
) -> Tile {
  let tolerance = if z == options.max_zoom {
    0.0
  } else {
    options.tolerance / ((1 << z).to_double() * options.extent.to_double())
  }
  let tile : Tile = {
    z,
    x,
    y,
    source: None,
    min_x: 2.0,
    min_y: 1.0,
    max_x: -1.0,
    max_y: 0.0,
    num_points: 0,
    types: [],
    rows: [],
    ring_ends: [],
    point_ends: [],
    coords: [],
    clips: [],
    data: None,
  }
  for fr in set {
    let store = fr.s
    let f = fr.i
    tile.min_x = @cmp.minimum(tile.min_x, store.min_x[f])
    tile.min_y = @cmp.minimum(tile.min_y, store.min_y[f])
    tile.max_x = @cmp.maximum(tile.max_x, store.max_x[f])
    tile.max_y = @cmp.maximum(tile.max_y, store.max_y[f])
    let rings_before = tile.point_ends.length()
    let kind = store.kind[f]
    if kind == 1 {
      let p = start(store.part_ends, f)
      let r = start(store.ring_ends, p)
      for i in start(store.point_ends, r)..<store.point_ends[r] {
        tile.coords.push(store.pts[i * 3])
        tile.coords.push(store.pts[i * 3 + 1])
        tile.num_points += 1
      }
      if tile.coords.length() / 2 > last_or_zero(tile.point_ends) {
        tile.point_ends.push(tile.coords.length() / 2)
      }
    } else {
      for p in start(store.part_ends, f)..<store.part_ends[f] {
        let r0 = start(store.ring_ends, p)
        for r in r0..<store.ring_ends[p] {
          add_line(tile, store, r, tolerance, kind == 3, r == r0)
        }
      }
    }
    if tile.point_ends.length() > rings_before {
      tile.types.push(kind)
      tile.rows.push(store.row[f])
      tile.ring_ends.push(tile.point_ends.length())
      if options.line_metrics {
        // geojson-vt's clip tags: a line's one slice, as shares of its length.
        let r = start(store.ring_ends, start(store.part_ends, f))
        if kind == 2 {
          tile.clips.push(store.from[r] / store.size[r])
          tile.clips.push(store.to[r] / store.size[r])
        } else {
          tile.clips.push(@double.not_a_number)
          tile.clips.push(@double.not_a_number)
        }
      }
    }
  }
  tile
}

///|
/// geojson-vt's `addLine`: ring `r` without the points unimportant at this
/// tolerance, or nothing if the whole ring is too small to show.
fn add_line(
  tile : Tile,
  store : Store,
  r : Int32,
  tolerance : Double,
  polygon : Bool,
  outer : Bool,
) -> Unit {
  let sq_tolerance = tolerance * tolerance
  let a = start(store.point_ends, r)
  let b = store.point_ends[r]
  if tolerance > 0.0 &&
    store.size[r] < (if polygon { sq_tolerance } else { tolerance }) {
    tile.num_points += b - a
    return
  }
  let first = tile.coords.length()
  for i in a..<b {
    if tolerance == 0.0 || store.pts[i * 3 + 2] > sq_tolerance {
      tile.coords.push(store.pts[i * 3])
      tile.coords.push(store.pts[i * 3 + 1])
    }
    tile.num_points += 1
  }
  if polygon {
    rewind(tile.coords, first, outer)
  }
  tile.point_ends.push(tile.coords.length() / 2)
}

///|
/// Reverses the ring starting at `first` (x, y pairs to the end of
/// `coords`) unless it already winds the way `clockwise` asks.
fn rewind(coords : Array[Double], first : Int32, clockwise : Bool) -> Unit {
  let len = coords.length() - first
  let mut area = 0.0
  let mut j = len - 2
  let mut i = 0
  while i < len {
    area += (coords[first + i] - coords[first + j]) *
      (coords[first + i + 1] + coords[first + j + 1])
    j = i
    i += 2
  }
  if (area > 0.0) != clockwise {
    return
  }
  let mut i = 0
  while i < len / 2 {
    let x = coords[first + i]
    let y = coords[first + i + 1]
    coords[first + i] = coords[first + len - 2 - i]
    coords[first + i + 1] = coords[first + len - 1 - i]
    coords[first + len - 2 - i] = x
    coords[first + len - 1 - i] = y
    i += 2
  }
}

///|
/// JavaScript's `Math.round`: halves go up, also below zero.
fn js_round(v : Double) -> Int32 {
  let r = v.floor()
  (if v - r >= 0.5 { r + 1.0 } else { r }).to_int()
}

///|
/// geojson-vt's `transformTile`: the tile's features in tile units.
fn Tile::transform(self : Tile, extent : Int32) -> TileData {
  if self.data is Some(d) {
    return d
  }
  let z2 = (1 << self.z).to_double()
  let e = extent.to_double()
  let xy = Array::make(self.coords.length(), 0)
  for i in 0..<(self.coords.length() / 2) {
    xy[i * 2] = js_round(e * (self.coords[i * 2] * z2 - self.x.to_double()))
    xy[i * 2 + 1] = js_round(
      e * (self.coords[i * 2 + 1] * z2 - self.y.to_double()),
    )
  }
  let d : TileData = {
    types: self.types,
    rows: self.rows,
    ring_ends: self.ring_ends,
    point_ends: self.point_ends,
    xy,
    clips: self.clips,
  }
  self.data = Some(d)
  d
}
