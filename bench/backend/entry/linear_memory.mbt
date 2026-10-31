// wasm / wasm-gc: read input from and write output to linear memory directly,
// so JS can wrap both sides in typed array views.

///|
extern "wasm" fn load_u8(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load8_u (local.get 0)))

///|
extern "wasm" fn store_f32(addr : Int32, v : Float) =
  #|(func (param i32) (param f32) (f32.store (local.get 0) (local.get 1)))

///|
extern "wasm" fn memory_grow(pages : Int32) -> Int32 =
  #|(func (param i32) (result i32) (memory.grow (local.get 0)))

///|
/// Grows linear memory by `pages` 64KiB pages; returns the previous size.
pub fn grow_memory(pages : Int32) -> Int32 {
  memory_grow(pages)
}

///|
/// Same algorithm as `@kernel.decode_deltas`, over raw addresses.
pub fn decode_mem(src : Int32, len : Int32, dst : Int32) -> Int32 {
  let end = src + len
  let mut pos = src
  let mut n = 0
  let mut x = 0
  let mut y = 0
  while pos < end {
    let mut b = load_u8(pos)
    pos += 1
    let mut v = b & 0x7f
    let mut shift = 7
    while b >= 0x80 {
      b = load_u8(pos)
      pos += 1
      v = v | ((b & 0x7f) << shift)
      shift += 7
    }
    let d = (v >> 1) ^ -(v & 1)
    if (n & 1) == 0 {
      x += d
      store_f32(dst + n * 4, Float::from_int(x))
    } else {
      y += d
      store_f32(dst + n * 4, Float::from_int(y))
    }
    n += 1
  }
  n
}

///|
/// Copies `len` bytes from linear memory at `addr` into `dst` inside wasm.
pub fn bytes_from_mem(
  addr : Int32,
  len : Int32,
  dst : FixedArray[Byte],
) -> Unit {
  for i in 0..<len {
    dst[i] = load_u8(addr + i).to_byte()
  }
}

///|
/// Copies the first `n` floats of `src` to linear memory at `addr` inside wasm.
pub fn floats_to_mem(src : FixedArray[Float], n : Int32, addr : Int32) -> Unit {
  for i in 0..<n {
    store_f32(addr + i * 4, src[i])
  }
}
