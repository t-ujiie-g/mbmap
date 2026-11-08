///|
let trig : @core.Trig = @wasmio.host_trig()

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
/// The input of every export: a table (`len_t` bytes, empty when 0), a UTF-8
/// text (`len_s` bytes: a property name) and the f64s after them.
priv struct Input {
  table : @geom.Table
  text : String
  numbers : Array[Double]
}

///|
fn input(len_t : Int32, len_s : Int32) -> Input? {
  let len = @wasmio.input_length()
  let fit = @wasmio.lengths_fit(len_t, len_s, len) &&
    (len - len_t - len_s) % 8 == 0
  let table = if len_t == 0 {
    Some(@geom.Table::new())
  } else {
    @wasmio.input_table(0, len_t)
  }
  let text = @core.utf8_lossy(@wasmio.input_slice(len_t, len_s)[:])
  let rest = if fit {
    @wasmio.input_slice(len_t + len_s, len - len_t - len_s)
  } else {
    Bytes::new(0)
  }
  @wasmio.clear_input()
  guard fit && table is Some(table) else { return None }
  let r = @core.ByteReader::new(rest[:])
  let numbers = Array::makei(rest.length() / 8, _ => r.f64())
  Some({ table, text, numbers, })
}

///|
/// Writes `out` as table bytes and returns their length, or minus `why`'s.
fn table(out : @geom.Table?, why : String) -> Int32 {
  match out {
    Some(t) => @wasmio.write_table(t)
    None => @wasmio.fail_with(why)
  }
}

///|
let malformed = "malformed input"

///|
/// One of Turf's grids over the box (`grid` 0 point, 1 square, 2 hex, 3
/// triangle; `triangles` 1 splits hexagons).
fn grid(
  len_t : Int32,
  len_s : Int32,
  kind : Int32,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cell : Double,
  triangles : Int32,
) -> Int32 {
  guard input(len_t, len_s) is Some(_) else {
    return @wasmio.fail_with(malformed)
  }
  let out = match kind {
    0 => @grids.point_grid(x0, y0, x1, y1, cell, trig~)
    1 => @grids.square_grid(x0, y0, x1, y1, cell, trig~)
    2 => @grids.hex_grid(x0, y0, x1, y1, cell, triangles=triangles != 0, trig~)
    _ => @grids.triangle_grid(x0, y0, x1, y1, cell, trig~)
  }
  table(
    out,
    "no grid: the cell side must be positive and the grid at most \{@grids.MAX_GRID_CELLS} cells",
  )
}

///|
/// Turf's `pointGrid` over the box.
#export_name("point_grid")
pub fn point_grid(
  len_t : Int32,
  len_s : Int32,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cell : Double,
  triangles : Int32,
) -> Int32 {
  grid(len_t, len_s, 0, x0, y0, x1, y1, cell, triangles)
}

///|
/// Turf's `squareGrid` over the box.
#export_name("square_grid")
pub fn square_grid(
  len_t : Int32,
  len_s : Int32,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cell : Double,
  triangles : Int32,
) -> Int32 {
  grid(len_t, len_s, 1, x0, y0, x1, y1, cell, triangles)
}

///|
/// Turf's `hexGrid` over the box.
#export_name("hex_grid")
pub fn hex_grid(
  len_t : Int32,
  len_s : Int32,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cell : Double,
  triangles : Int32,
) -> Int32 {
  grid(len_t, len_s, 2, x0, y0, x1, y1, cell, triangles)
}

///|
/// Turf's `triangleGrid` over the box.
#export_name("triangle_grid")
pub fn triangle_grid(
  len_t : Int32,
  len_s : Int32,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  cell : Double,
  triangles : Int32,
) -> Int32 {
  grid(len_t, len_s, 3, x0, y0, x1, y1, cell, triangles)
}

///|
/// Turf's `interpolate` of the table's points by the property named by the text.
#export_name("interpolate")
pub fn interpolate(
  len_t : Int32,
  len_s : Int32,
  cell : Double,
  kind : Int32,
  weight : Double,
) -> Int32 {
  guard input(len_t, len_s) is Some(i) else {
    return @wasmio.fail_with(malformed)
  }
  table(
    @grids.interpolate(i.table, cell, kind, i.text, weight, trig~),
    "no interpolation: every point needs a number in \{i.text}, and the grid at most \{@grids.MAX_GRID_CELLS} cells",
  )
}

///|
/// Turf's `isolines` of the table's point grid at the f64 breaks.
#export_name("isolines")
pub fn isolines(len_t : Int32, len_s : Int32) -> Int32 {
  guard input(len_t, len_s) is Some(i) else {
    return @wasmio.fail_with(malformed)
  }
  table(
    @isolines.isolines(i.table, i.numbers, i.text),
    "no isolines: the points must form a grid with numbers in \{i.text}",
  )
}

///|
/// Turf's `isobands` of the table's point grid between the f64 breaks.
#export_name("isobands")
pub fn isobands(len_t : Int32, len_s : Int32) -> Int32 {
  guard input(len_t, len_s) is Some(i) else {
    return @wasmio.fail_with(malformed)
  }
  table(
    @isolines.isobands(
      i.table,
      i.numbers,
      i.text,
      trig~,
      number_text=@wasmio.host_number_to_text,
    ),
    "no isobands: the points must form a grid with numbers in \{i.text}",
  )
}

///|
/// d3-contour's `contourDensity` of the table's points on a `width` x `height`
/// grid over the box (theirs where NaN), weighted by the text's property when
/// `weighted` is 1: a MultiPolygon row with its `value` per contour.
#export_name("density")
pub fn density(
  len_t : Int32,
  len_s : Int32,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  width : Double,
  height : Double,
  cell : Double,
  bandwidth : Double,
  thresholds : Double,
  weighted : Int32,
) -> Int32 {
  guard input(len_t, len_s) is Some(i) else {
    return @wasmio.fail_with(malformed)
  }
  let t = i.table
  let xs = []
  let ys = []
  let ws = []
  let column = if weighted != 0 { t.column(i.text) } else { None }
  for row in 0..<t.length() {
    guard t.kinds[row] is Point else { continue }
    let (ps, pe) = t.parts(row)
    guard pe > ps else { continue }
    let (rs, re) = t.rings(ps)
    guard re > rs else { continue }
    let (p0, p1) = t.points(rs)
    guard p1 > p0 && 2 * p0 + 1 < t.coords.length() else { continue }
    xs.push(t.coords[2 * p0])
    ys.push(t.coords[2 * p0 + 1])
    ws.push(
      match column {
        Some(c) =>
          match c.values[row] {
            Some(Num(v)) => v
            _ => 0.0
          }
        None => 1.0
      },
    )
  }
  let (bx0, by0, bx1, by1) = if [x0, y0, x1, y1].iter().any(v => v.is_nan()) {
    let mut b = (
      @double.infinity, @double.infinity, @double.neg_infinity, @double.neg_infinity,
    )
    for k in 0..<xs.length() {
      b = (
        @cmp.minimum(b.0, xs[k]),
        @cmp.minimum(b.1, ys[k]),
        @cmp.maximum(b.2, xs[k]),
        @cmp.maximum(b.3, ys[k]),
      )
    }
    b
  } else {
    (x0, y0, x1, y1)
  }
  let (w, h) = (width.to_int(), height.to_int())
  guard w > 0 && h > 0 && bx1 > bx0 && by1 > by0 else {
    return @wasmio.fail_with("no density: an empty box or size")
  }
  let (sx, sy) = (bx1 - bx0, by1 - by0)
  let px = FixedArray::makei(xs.length(), k => (xs[k] - bx0) / sx * width)
  let py = FixedArray::makei(ys.length(), k => (by1 - ys[k]) / sy * height)
  let weights = if weighted != 0 {
    Some(FixedArray::from_array(ws))
  } else {
    None
  }
  guard @density.contour_density(
      px,
      py,
      weights,
      w,
      h,
      cell.to_int(),
      bandwidth,
      thresholds.to_int(),
      trig~,
    )
    is Some(contours) else {
    return @wasmio.fail_with("no density: too many cells or thresholds")
  }
  let b = @geom.TableBuilder::new()
  for c in contours {
    for polygon in c.coordinates {
      for ring in polygon {
        for p in ring {
          b.point(bx0 + p.0 / width * sx, by1 - p.1 / height * sy)
        }
        b.end_ring()
      }
      b.end_part()
    }
    b.prop("value", Num(c.value))
    b.end_feature(MultiPolygon)
  }
  @wasmio.write_table(b.finish())
}

///|
/// Turf's `clustersDbscan` of the table's points: two f64s a row (cluster or
/// -1, `@clusters.DBSCAN_*`); returns the f64 count.
#export_name("dbscan")
pub fn dbscan(
  len_t : Int32,
  len_s : Int32,
  max_distance : Double,
  min_points : Double,
) -> Int32 {
  guard input(len_t, len_s) is Some(i) else {
    return @wasmio.fail_with(malformed)
  }
  guard @wasmio.output_fits(2L * i.table.length().to_int64(), 8) else {
    return -2
  }
  guard @clusters.dbscan(i.table, max_distance, min_points.to_int(), trig~)
    is Some(out) else {
    return @wasmio.fail_with(too_many)
  }
  @wasmio.write_f64s(FixedArray::makei(out.length(), k => out[k].to_double()))
}

///|
let too_many = "more than \{@clusters.MAX_CLUSTER_POINTS} points, or too much work"

///|
/// Turf's `clustersKmeans` of the table's points (`k` 0 for Turf's default):
/// the row count, each row's cluster (-1 when not a point), then the centroids
/// as x, y; returns the f64 count.
#export_name("kmeans")
pub fn kmeans(len_t : Int32, len_s : Int32, k : Double) -> Int32 {
  guard input(len_t, len_s) is Some(i) else {
    return @wasmio.fail_with(malformed)
  }
  guard @clusters.kmeans(i.table, k.to_int()) is Some((rows, centroids)) else {
    return @wasmio.fail_with(too_many)
  }
  let n = rows.length()
  guard @wasmio.output_fits(
    1L + n.to_int64() + centroids.length().to_int64(),
    8,
  ) else {
    return -2
  }
  @wasmio.write_f64s(
    FixedArray::makei(1 + n + centroids.length(), j => {
      if j == 0 {
        n.to_double()
      } else if j <= n {
        rows[j - 1].to_double()
      } else {
        centroids[j - 1 - n]
      }
    }),
  )
}
