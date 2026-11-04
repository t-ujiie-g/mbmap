///|
/// Places `json` as the input, as the glue does before `load`.
fn put_input(json : Bytes) -> Unit {
  let at = @wasmio.prepare_input(json.length(), @wasmio.MAX_INPUT_BYTES)
  for i, b in json {
    store_u8(at + i, b.to_int())
  }
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
