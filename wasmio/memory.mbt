///|
extern "wasm" fn load_u8(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load8_u (local.get 0)))

///|
extern "wasm" fn load_i32(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load align=1 (local.get 0)))

///|
extern "wasm" fn load_f64(addr : Int32) -> Double =
  #|(func (param i32) (result f64) (f64.load align=1 (local.get 0)))

///|
extern "wasm" fn store_u8(addr : Int32, v : Int32) =
  #|(func (param i32) (param i32) (i32.store8 (local.get 0) (local.get 1)))

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
/// Where input starts: one 64KiB page in.
pub const PAGE : Int32 = 65536

///|
/// Largest input the entries accept (AGENTS.md §8.2: limit the size before
/// reading).
pub const MAX_INPUT_BYTES : Int32 = 256 * 1024 * 1024

///|
/// Largest output written; results are a few numbers per feature at most.
const MAX_OUTPUT_BYTES : Int32 = 1024 * 1024 * 1024

///|
let input_len : Ref[Int32] = Ref(0)

///|
fn ensure_memory(bytes : Int32) -> Bool {
  let have = memory_size() * PAGE
  bytes <= have || memory_grow((bytes - have + PAGE - 1) / PAGE) >= 0
}

///|
/// Makes room for `len` input bytes and returns where JS should write them,
/// or -1 if `len` is negative, over `max` or past what memory can grow to.
pub fn prepare_input(len : Int32, max : Int32) -> Int32 {
  if len < 0 || len > max || !ensure_memory(PAGE + len) {
    return -1
  }
  input_len.val = len
  PAGE
}

///|
/// Forgets the input, so output starts right after `PAGE`.
pub fn clear_input() -> Unit {
  input_len.val = 0
}

///|
/// Where output starts: after the input, 8-byte aligned.
pub fn output_addr() -> Int32 {
  (PAGE + input_len.val + 7) / 8 * 8
}

///|
/// How many input bytes `prepare_input` made room for.
pub fn input_length() -> Int32 {
  input_len.val
}

///|
/// Whether `count` values of `size` bytes fit the output, so an entry can check
/// before it builds them.
pub fn output_fits(count : Int64, size : Int32) -> Bool {
  count >= 0L && count * size.to_int64() <= MAX_OUTPUT_BYTES.to_int64()
}

///|
/// Whether parts of `a` then `b` bytes fit in `total` (without overflowing).
pub fn lengths_fit(a : Int32, b : Int32, total : Int32) -> Bool {
  a >= 0 && b >= 0 && a <= total && b <= total - a
}

///|
/// The input copied into a `Bytes`, four bytes per load.
pub fn input_bytes() -> Bytes {
  let len = input_len.val
  let arr = FixedArray::make(len, b'\x00')
  let words = len / 4
  for w in 0..<words {
    let v = load_i32(PAGE + w * 4)
    let i = w * 4
    arr[i] = v.to_byte()
    arr[i + 1] = (v >> 8).to_byte()
    arr[i + 2] = (v >> 16).to_byte()
    arr[i + 3] = (v >> 24).to_byte()
  }
  for i in (words * 4)..<len {
    arr[i] = load_u8(PAGE + i).to_byte()
  }
  // Nothing else holds `arr`, so the reinterpretation cannot be observed mutating.
  arr.unsafe_reinterpret_as_bytes()
}

///|
/// Input bytes `[start, start + len)` copied into a `Bytes`, four bytes per
/// load; empty unless they are all input.
pub fn input_slice(start : Int32, len : Int32) -> Bytes {
  guard lengths_fit(start, len, input_len.val) else { return Bytes::new(0) }
  let arr = FixedArray::make(len, b'\x00')
  let words = len / 4
  let at = PAGE + start
  for w in 0..<words {
    let v = load_i32(at + w * 4)
    let i = w * 4
    arr[i] = v.to_byte()
    arr[i + 1] = (v >> 8).to_byte()
    arr[i + 2] = (v >> 16).to_byte()
    arr[i + 3] = (v >> 24).to_byte()
  }
  for i in (words * 4)..<len {
    arr[i] = load_u8(at + i).to_byte()
  }
  // Nothing else holds `arr`, so the reinterpretation cannot be observed mutating.
  arr.unsafe_reinterpret_as_bytes()
}

///|
/// The input read as f64s (a trailing part of one is left out).
pub fn input_f64s() -> FixedArray[Double] {
  let out = FixedArray::make(input_len.val / 8, 0.0)
  for i in 0..<out.length() {
    out[i] = load_f64(PAGE + i * 8)
  }
  out
}

///|
/// Makes room for `bytes` of output; false if it is too large.
fn reserve(bytes : Int32) -> Bool {
  bytes >= 0 &&
  bytes <= MAX_OUTPUT_BYTES &&
  ensure_memory(output_addr() + bytes)
}

///|
/// Writes `bytes` to the output; returns their length, or -2 without memory.
pub fn write_bytes(bytes : BytesView) -> Int32 {
  guard reserve(bytes.length()) else { return -2 }
  let at = output_addr()
  for i, b in bytes {
    store_u8(at + i, b.to_int())
  }
  bytes.length()
}

///|
/// Writes `values` as f64s to the output; returns their count, or -2 without
/// memory.
pub fn write_f64s(values : FixedArray[Double]) -> Int32 {
  let n = values.length()
  guard n <= MAX_OUTPUT_BYTES / 8 && reserve(n * 8) else { return -2 }
  let at = output_addr()
  for i, v in values {
    store_f64(at + i * 8, v)
  }
  n
}

///|
/// Writes `head` then `values` as f64s to the output; returns their count, or
/// -2 without memory.
pub fn write_f64s_after(
  head : FixedArray[Double],
  values : FixedArray[Double],
) -> Int32 {
  let h = head.length()
  let n = h + values.length()
  guard n >= h && n <= MAX_OUTPUT_BYTES / 8 && reserve(n * 8) else { return -2 }
  let at = output_addr()
  for i, v in head {
    store_f64(at + i * 8, v)
  }
  let at = at + h * 8
  for i, v in values {
    store_f64(at + i * 8, v)
  }
  n
}

///|
/// Writes the `w` x `h` cells from (`x`, `y`) of a grid `stride` cells wide,
/// `values` row by row, as f64s; returns their count, -1 if they are not all in
/// the grid, or -2 without memory.
pub fn write_f64_rows(
  values : FixedArray[Double],
  stride : Int32,
  x : Int32,
  y : Int32,
  w : Int32,
  h : Int32,
) -> Int32 {
  guard stride > 0 &&
    lengths_fit(x, w, stride) &&
    y >= 0 &&
    h >= 0 &&
    (y.to_int64() + h.to_int64()) * stride.to_int64() <=
    values.length().to_int64() else {
    return -1
  }
  let n = w * h
  guard n <= MAX_OUTPUT_BYTES / 8 && reserve(n * 8) else { return -2 }
  let mut at = output_addr()
  for row in y..<(y + h) {
    let base = row * stride + x
    for i in 0..<w {
      store_f64(at + i * 8, values[base + i])
    }
    at += w * 8
  }
  n
}

///|
/// Writes `values` as i32s to the output; returns their count, or -2 without
/// memory.
pub fn write_i32s(values : ArrayView[Int32]) -> Int32 {
  let n = values.length()
  guard n <= MAX_OUTPUT_BYTES / 4 && reserve(n * 4) else { return -2 }
  let at = output_addr()
  for i, v in values {
    store_i32(at + i * 4, v)
  }
  n
}

///|
/// Writes `message` as UTF-8 to the output; returns minus its length, or -2
/// without memory.
pub fn fail_with(message : String) -> Int32 {
  let n = write_bytes(@utf8.encode(message)[:])
  if n < 0 {
    n
  } else {
    -n
  }
}

///|
/// The JSON number at `[addr, addr + len)` of linear memory, by the host's
/// `Number()`: correctly rounded like strconv, which it keeps out of the module.
fn host_number(addr : Int32, len : Int32) -> Double = "host" "number"

///|
/// The number at input bytes `[start, end)` by the host's `Number()`: a
/// `slow_number` for `@formats.read_geojson` over `input_bytes`.
pub fn input_number(start : Int32, end : Int32) -> Double {
  host_number(PAGE + start, end - start)
}
