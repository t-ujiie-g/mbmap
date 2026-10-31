///|
fn host_sin(x : Double) -> Double = "Math" "sin"

///|
fn host_cos(x : Double) -> Double = "Math" "cos"

///|
fn host_atan2(y : Double, x : Double) -> Double = "Math" "atan2"

///|
/// The JSON number at `[addr, addr + len)` of linear memory, by the host's
/// `Number()` (correctly rounded, as strconv is, and far smaller).
fn host_number(addr : Int32, len : Int32) -> Double = "host" "number"

///|
/// The host's `Math`, so measures match Turf bit for bit.
let trig : @analysis.Trig = { sin: host_sin, cos: host_cos, atan2: host_atan2, }

///|
priv struct Dataset {
  table : @geom.Table
  mut index : @analysis.Index?
}

///|
fn Dataset::index(self : Dataset) -> @analysis.Index {
  match self.index {
    Some(i) => i
    None => {
      let i = @analysis.Index::of_table(self.table)
      self.index = Some(i)
      i
    }
  }
}

///|
let datasets : Map[Int32, Dataset] = Map([])

///|
let next_id : Ref[Int32] = Ref(0)

///|
/// Reads the GeoJSON placed as input into a new dataset. Returns its handle,
/// or minus the length of a UTF-8 error message at `output_addr`.
#export_name("load")
pub fn load() -> Int32 {
  let input = input_bytes()
  let table = @formats.read_geojson(input[:], slow_number=(s, e) => {
    host_number(PAGE + s, e - s)
  }) catch {
    e => return fail_with(e.message())
  }
  let id = next_id.val
  next_id.val += 1
  datasets[id] = { table, index: None, }
  input_len.val = 0
  id
}

///|
/// The number of features of dataset `id`, or -1 if there is none.
#export_name("feature_count")
pub fn feature_count(id : Int32) -> Int32 {
  match datasets.get(id) {
    Some(d) => d.table.length()
    None => -1
  }
}

///|
/// Frees dataset `id`.
#export_name("dispose")
pub fn dispose(id : Int32) -> Unit {
  datasets.remove(id)
}

///|
/// Measure kinds of `measure`: f64s per feature.
const MEASURE_AREA : Int32 = 0

///|
const MEASURE_LENGTH : Int32 = 1

///|
const MEASURE_CENTROID : Int32 = 2

///|
const MEASURE_BBOX : Int32 = 3

///|
/// Writes a measure of every feature of dataset `id` as f64s: area (m²) or
/// length (m), one each; centroid, two; bbox, four. Returns the f64 count,
/// or -1 for an unknown dataset or kind.
#export_name("measure")
pub fn measure(id : Int32, kind : Int32) -> Int32 {
  guard datasets.get(id) is Some(d) else { return -1 }
  let t = d.table
  let n = t.length()
  input_len.val = 0
  let out = if kind == MEASURE_AREA {
    FixedArray::makei(n, f => @analysis.area(t, trig, f))
  } else if kind == MEASURE_LENGTH {
    FixedArray::makei(n, f => @analysis.length(t, trig, f))
  } else if kind == MEASURE_CENTROID {
    let a = FixedArray::make(n * 2, 0.0)
    for f in 0..<n {
      let (x, y) = @analysis.centroid(t, f)
      a[f * 2] = x
      a[f * 2 + 1] = y
    }
    a
  } else if kind == MEASURE_BBOX {
    let a = FixedArray::make(n * 4, 0.0)
    for f in 0..<n {
      let (x0, y0, x1, y1) = @analysis.bbox(t, f)
      a[f * 4] = x0
      a[f * 4 + 1] = y0
      a[f * 4 + 2] = x1
      a[f * 4 + 3] = y1
    }
    a
  } else {
    return -1
  }
  write_f64s(out)
}

///|
/// Writes the features of dataset `id` whose boxes meet the box as i32s, in
/// index order. Returns their count, or -1 for an unknown dataset.
#export_name("search")
pub fn search(
  id : Int32,
  min_x : Double,
  min_y : Double,
  max_x : Double,
  max_y : Double,
) -> Int32 {
  guard datasets.get(id) is Some(d) else { return -1 }
  input_len.val = 0
  let out = []
  d.index().search(min_x, min_y, max_x, max_y, out)
  write_i32s(out[:])
}

///|
/// Writes up to `k` features of dataset `id` by box distance from (x, y)
/// within `max_distance`, nearest first. Returns their count, or -1 for an
/// unknown dataset.
#export_name("nearest")
pub fn nearest(
  id : Int32,
  x : Double,
  y : Double,
  k : Int32,
  max_distance : Double,
) -> Int32 {
  guard datasets.get(id) is Some(d) else { return -1 }
  input_len.val = 0
  let out = []
  d.index().neighbors(x, y, out, max_results=k, max_distance~)
  write_i32s(out[:])
}

///|
/// Writes the point features of dataset `points` within some polygon of
/// dataset `polygons`. Returns their count, or -1 for an unknown dataset.
#export_name("within")
pub fn within(points : Int32, polygons : Int32) -> Int32 {
  guard datasets.get(points) is Some(p) && datasets.get(polygons) is Some(q) else {
    return -1
  }
  input_len.val = 0
  write_i32s(@analysis.points_within(p.table, q.table, q.index())[:])
}

///|
/// Writes `@analysis.collect` of dataset `polygons` over dataset `points` for
/// the property named by the UTF-8 input (three f64s per polygon). Returns the
/// f64 count, or -1 for an unknown dataset.
#export_name("collect")
pub fn collect(polygons : Int32, points : Int32) -> Int32 {
  guard datasets.get(polygons) is Some(q) && datasets.get(points) is Some(p) else {
    return -1
  }
  let column = @utf8.decode_lossy(input_bytes())
  input_len.val = 0
  write_f64s(@analysis.collect(q.table, p.table, p.index(), column))
}

///|
/// Writes `@analysis.grid_count` of dataset `id` as i32s. Returns the cell
/// count, or -1 for an unknown dataset or an invalid grid.
#export_name("grid")
pub fn grid(
  id : Int32,
  min_x : Double,
  min_y : Double,
  max_x : Double,
  max_y : Double,
  cols : Int32,
  rows : Int32,
) -> Int32 {
  guard datasets.get(id) is Some(d) else { return -1 }
  input_len.val = 0
  match @analysis.grid_count(d.table, min_x, min_y, max_x, max_y, cols, rows) {
    Some(cells) => write_i32s(cells[:])
    None => -1
  }
}
