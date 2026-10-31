// Input at PAGE: i32 ring ends, i32 polygon ends, f64 coordinates. Output
// follows: per polygon area and bbox (5 f64), the 10 largest (i32), the
// non-empty 1° cell count (i32).

///|
extern "wasm" fn load_i32(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load align=1 (local.get 0)))

///|
extern "wasm" fn load_f64(addr : Int32) -> Double =
  #|(func (param i32) (result f64) (f64.load align=1 (local.get 0)))

///|
extern "wasm" fn store_i32(addr : Int32, v : Int32) =
  #|(func (param i32) (param i32) (i32.store align=1 (local.get 0) (local.get 1)))

///|
extern "wasm" fn store_f64(addr : Int32, v : Double) =
  #|(func (param i32) (param f64) (f64.store align=1 (local.get 0) (local.get 1)))

///|
extern "wasm" fn memory_size() -> Int32 =
  #|(func (result i32) (memory.size))

///|
extern "wasm" fn memory_grow(pages : Int32) -> Int32 =
  #|(func (param i32) (result i32) (memory.grow (local.get 0)))

///|
const PAGE : Int32 = 65536

///|
let input_len : Ref[Int32] = Ref(0)

///|
fn ensure_memory(bytes : Int32) -> Bool {
  let have = memory_size() * PAGE
  bytes <= have || memory_grow((bytes - have + PAGE - 1) / PAGE) >= 0
}

///|
fn output_start() -> Int32 {
  (PAGE + input_len.val + 7) / 8 * 8
}

///|
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  if len < 0 || !ensure_memory(PAGE + len) {
    return -1
  }
  input_len.val = len
  PAGE
}

///|
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  output_start()
}

///|
/// Runs the analysis on the input; returns the output length, or -1 if the
/// counts do not match the input length.
#export_name("analyze")
pub fn analyze(n_rings : Int32, n_polys : Int32, n_points : Int32) -> Int32 {
  // Bound each count by the input before multiplying, so the size check
  // cannot overflow (AGENTS.md §8.2).
  let len = input_len.val
  if n_rings < 0 ||
    n_polys < 0 ||
    n_points < 0 ||
    n_rings > len / 4 ||
    n_polys > len / 4 ||
    n_points > len / 16 ||
    (n_rings + n_polys) * 4 + n_points * 16 != len {
    return -1
  }
  let ring_ends = FixedArray::makei(n_rings, i => load_i32(PAGE + i * 4))
  let poly_ends = FixedArray::makei(n_polys, i => {
    load_i32(PAGE + (n_rings + i) * 4)
  })
  let at = PAGE + (n_rings + n_polys) * 4
  let coords = FixedArray::makei(n_points * 2, i => load_f64(at + i * 8))
  let p : @analysis.Polygons = { coords, ring_ends, poly_ends, }
  let out = output_start()
  let out_len = n_polys * 40 + 44
  if !ensure_memory(out + out_len) {
    return -1
  }
  for i in 0..<n_polys {
    let (w, s, e, n) = p.bbox(i)
    let o = out + i * 40
    store_f64(o, p.area(i))
    store_f64(o + 8, w)
    store_f64(o + 16, s)
    store_f64(o + 24, e)
    store_f64(o + 32, n)
  }
  let top = p.largest(10)
  for i in 0..<10 {
    store_i32(
      out + n_polys * 40 + i * 4,
      if i < top.length() {
        top[i]
      } else {
        -1
      },
    )
  }
  store_i32(out + n_polys * 40 + 40, p.grid_counts(1.0).length())
  out_len
}
