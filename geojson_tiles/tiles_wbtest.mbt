///|
/// Places `bytes` as the input.
fn put_bytes(bytes : Bytes) -> Unit {
  let at = @wasmio.prepare_input(bytes.length(), @wasmio.MAX_INPUT_BYTES)
  for i, b in bytes {
    store_u8(at + i, b.to_int())
  }
}

///|
/// `head` with its u32 length before it, then `rest`.
fn sized(head : Bytes, rest : Bytes) -> Bytes {
  let w = @core.ByteWriter::new()
  w.u32(head.length())
  let out = w.to_bytes().to_array()
  out.push_iter(head.iter())
  out.push_iter(rest.iter())
  Bytes::from_array(out)
}

///|
/// Places `json` as the input, as the glue does before `load` (`promote_id` first).
fn put_input(json : Bytes, promote_id~ : Bytes = b"") -> Unit {
  put_bytes(sized(promote_id, json))
}

///|
extern "wasm" fn store_u8(addr : Int32, v : Int32) =
  #|(func (param i32) (param i32) (i32.store8 (local.get 0) (local.get 1)))

///|
extern "wasm" fn load_u8(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load8_u (local.get 0)))

///|
fn load_test(
  source : Int32,
  max_zoom~ : Int32 = 14,
  buffer~ : Double = 64.0,
  cluster~ : Int32 = 0,
) -> Int32 {
  load(
    source,
    max_zoom,
    buffer,
    3.0,
    0,
    cluster,
    14,
    50.0,
    2,
    @core.Trig::moonbit(),
    (_, _) => panic(),
  )
}

///|
fn load_plain(source : Int32, json : Bytes) -> Int32 {
  put_input(json)
  load_test(source)
}

///|
test "a loaded source cuts tiles until it is unloaded" {
  let json = b"{\"type\":\"Feature\",\"properties\":{\"a\":1},\"geometry\":{\"type\":\"Point\",\"coordinates\":[10,20]}}"
  assert_eq(load_plain(7, json), 1)
  assert_eq(clustered(7), 0)
  let n = tile(7, 0, 0, 0)
  assert_true(n > 0)
  // The first u32 of a columnar tile is its feature count.
  assert_eq(load_u8(@wasmio.output_addr()), 1)
  assert_eq(tile(7, 2, 3, 3), 0)
  assert_eq(tile(8, 0, 0, 0), -1)
  unload(7)
  assert_eq(tile(7, 0, 0, 0), -1)
  assert_eq(clustered(7), -1)
}

///|
test "options out of range and unreadable GeoJSON are refused with a message" {
  put_input(b"{}")
  assert_true(load_test(1, max_zoom=@tiler.MAX_ZOOM + 1) < 0)
  assert_true(load_test(1, buffer=-1.0) < 0)
  assert_true(load_plain(1, b"{\"type\":") < 0)
  assert_eq(clustered(1), -1)
}

///|
test "clustered sources answer expansion zooms, children and leaves" {
  let json = b"{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{},\"geometry\":{\"type\":\"MultiPoint\",\"coordinates\":[[10,20],[10.001,20.001],[10.002,20]]}}]}"
  put_input(json)
  assert_eq(load_test(3, cluster=1), 1)
  assert_eq(clustered(3), 1)
  assert_true(tile(3, 0, 0, 0) > 0)
  assert_eq(cluster_children(3, 12345), -1)
  assert_eq(cluster_leaves(3, 12345, 10, 0), -1)
  assert_eq(cluster_expansion_zoom(9, 0), 0)
  assert_eq(cluster_children(9, 0), -1)
  unload(3)
}

///|
test "update applies a diff to a loaded source, found by its promoteId" {
  let json = b"{\"type\":\"Feature\",\"properties\":{\"k\":5},\"geometry\":{\"type\":\"Point\",\"coordinates\":[10,20]}}"
  put_input(json, promote_id=b"k")
  assert_eq(load_test(4), 1)
  // Removes the feature whose `k` is 5, then adds one at the same place.
  let w = @core.ByteWriter::new()
  w.u8(0)
  w.u32(1)
  @geom.write_prop(w, Some(Num(5.0)))
  w.u32(1)
  w.u32(0)
  let added = b"{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"k\":6},\"geometry\":{\"type\":\"Point\",\"coordinates\":[10,20]}}]}"
  put_bytes(sized(added, w.to_bytes()))
  assert_eq(update(4, (_, _) => panic()), 1)
  assert_true(tile(4, 0, 0, 0) > 0)
  // Nothing left to remove: no change.
  let none = @core.ByteWriter::new()
  none.u8(0)
  none.u32(1)
  @geom.write_prop(none, Some(Num(5.0)))
  none.u32(0)
  none.u32(0)
  put_bytes(
    sized(b"{\"type\":\"FeatureCollection\",\"features\":[]}", none.to_bytes()),
  )
  assert_eq(update(4, (_, _) => panic()), 0)
  // A diff that does not match its features, and a source not loaded, are refused.
  put_bytes(sized(added, b"\x00"))
  assert_true(update(4, (_, _) => panic()) < 0)
  put_bytes(b"\x01")
  assert_true(update(4, (_, _) => panic()) < 0)
  assert_true(update(99, (_, _) => panic()) < 0)
  unload(4)
}
