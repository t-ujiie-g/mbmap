///|
extern "wasm" fn load_u8(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load8_u (local.get 0)))

///|
extern "wasm" fn load_i32(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load align=1 (local.get 0)))

///|
extern "wasm" fn store_i32(addr : Int32, v : Int32) =
  #|(func (param i32) (param i32) (i32.store align=1 (local.get 0) (local.get 1)))

///|
extern "wasm" fn store_i16(addr : Int32, v : Int32) =
  #|(func (param i32) (param i32) (i32.store16 align=1 (local.get 0) (local.get 1)))

///|
extern "wasm" fn store_u8(addr : Int32, v : Int32) =
  #|(func (param i32) (param i32) (i32.store8 (local.get 0) (local.get 1)))

///|
extern "wasm" fn memory_copy(dst : Int32, src : Int32, n : Int32) =
  #|(func (param i32) (param i32) (param i32) (memory.copy (local.get 0) (local.get 1) (local.get 2)))

///|
extern "wasm" fn memory_size() -> Int32 =
  #|(func (result i32) (memory.size))

///|
extern "wasm" fn memory_grow(pages : Int32) -> Int32 =
  #|(func (param i32) (result i32) (memory.grow (local.get 0)))

///|
const PAGE : Int32 = 65536

///|
/// Grows linear memory to at least `bytes`; false if the engine refuses.
fn ensure_memory(bytes : Int32) -> Bool {
  let have = memory_size() * PAGE
  if bytes <= have {
    return true
  }
  memory_grow((bytes - have + PAGE - 1) / PAGE) >= 0
}

///|
/// Backing bytes of a `PackedTile` in wasm-gc: linear memory from `base` on,
/// where JS reads the result without a copy. Only the wasm-gc worker owns its
/// linear memory; in the wasm backend MoonBit's heap lives there.
priv struct Store {
  mut base : Int32
}

///|
fn Store::new() -> Store {
  { base: PAGE, }
}

///|
fn Store::ensure(self : Store, need : Int32, _keep : Int32) -> Bool {
  ensure_memory(self.base + need)
}

///|
fn Store::set_u8(self : Store, at : Int32, v : Int32) -> Unit {
  store_u8(self.base + at, v)
}

///|
fn Store::set_u16(self : Store, at : Int32, v : Int32) -> Unit {
  store_i16(self.base + at, v)
}

///|
fn Store::set_u32(self : Store, at : Int32, v : Int32) -> Unit {
  store_i32(self.base + at, v)
}

///|
fn Store::get_u32(self : Store, at : Int32) -> Int32 {
  load_i32(self.base + at)
}

///|
fn Store::zero(self : Store, start : Int32, end : Int32) -> Unit {
  for i in start..<end {
    store_u8(self.base + i, 0)
  }
}

///|
fn Store::copy_out(self : Store, len : Int32) -> Bytes {
  Bytes::makei(len, i => load_u8(self.base + i).to_byte())
}

///|
/// Repeats the `len` bytes at `at` until `total` bytes from `at` are filled,
/// doubling the copied run each time.
fn Store::repeat(self : Store, at : Int32, len : Int32, total : Int32) -> Unit {
  let mut filled = len
  while filled < total {
    let n = @cmp.minimum(filled, total - filled)
    memory_copy(self.base + at + filled, self.base + at, n)
    filled += n
  }
}

///|
/// Makes the next tile be packed at `addr` in linear memory.
fn PackedTile::place_at(self : PackedTile, addr : Int32) -> Unit {
  self.store.base = addr
}
