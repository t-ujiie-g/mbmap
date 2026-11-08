// Encoded by draco3d 1.5.7's encoder from twelve points (`legacy_float` is `kd0_u32`'s tree in the
// framing of bitstream 2.2's float kd-tree); the expected attribute values (by FNV-1a hash) are
// what draco3d 1.5.7's decoder gives.

///|
let pc_sequential : String = "445241434f0203000000000c0000000103000903000002020301010403020002020101000101000c2b01400100720f0071e3febfc24b87e17e6879b0c4af4d6e77faa4f2e718d0b371f0b9a09d75a41f6d8c7d4e45d3afa8e21ff0389a760f00000000ff0700000001010102df01c901ff23c901ff23c9017b1d17a38d2309fb452a386be146908200000000ea000000000101000d2f014001005c9b49d7788d333993d7389333798d333993d7788d333993d7389333798d333993d7788d24faffffad0500005f2114c1b45f1fc1dd7c1bc126059f410b"

///|
let pc_kd6 : String = "445241434f0203000100000c0000000103000903000002020301010403020002060c0000000c0000003d04e753ba484d0394054cff0288400101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101000101008000000000c6e70613783826000809a38d0452052187263cc38a682eff03ea14d3f743a8fca28982261ae3e41b1f7b5c1ee742c9f31f004d80c20a1c11ca0d7550c4e22b80620f56b2292f6e9c43139fed1a0306a82838e3c2c10b001e47a801c425f9ef4a280100b95b0800def0faff42a1600085a5a349172400fc42e5350500481b01040000000000000004000000006062005f2114c1b45f1fc1dd7c1bc126059f410bb717c511"

///|
let pc_kd0 : String = "445241434f0203000100000c00000001020009030000020203010100080000000c000000040000000000000344000000c719e4bf7950d70465b1a2ffe31f402e8d4c9bdfff1d686f559600dce84a162f1d28037572f1ae6162af1598009f70670dc2f118c003c8efa4f81ec3d54bb9f30034d504040000000000000004000000000000845f2114c1b45f1fc1dd7c1bc126059f4108"

///|
let pc_kd3_u32 : String = "445241434f0203000100000c00000001010006030000030a0000000c0000005b06911d41fa108224000000c02d8bdc53a4116ff8e0fcf573c417c00026ad339b1ee09894d0aef0df43c97e0000006d040000000000000004000000001c0d9d"

///|
let pc_kd0_u32 : String = "445241434f0203000100000c00000001010006030000000a0000000c00000004000000bc67bf1924000000c02d8bdc53a4116ff8e0fcf573c417c00026ad339b1ee09894d0aef0df43c97e0000006d040000000000000004000000001c0d9d"

///|
let pc_raw : String = "445241434f0203000000000300000001010009030000000000000097aa1e41db8b23c05f2114c1c41d9e401084ff40bcf5dfc0cbcdc5c045770941"

///|
let pc_legacy_float : String = "445241434f0202000100000c0000000101000903000000000c00000003000000010a000000000000400c000000000000000a0000000c00000004000000bc67bf1924000000c02d8bdc53a4116ff8e0fcf573c417c00026ad339b1ee09894d0aef0df43c97e0000006d040000000000000004000000001c0d9d"

///|
fn points(s : String) -> @draco.DracoMesh {
  let src = hex(s)
  @draco.decode_point_cloud(src, 0, src.length()).unwrap()
}

///|
test "decode_point_cloud: sequential, quantized positions, normalized colors and int16 values" {
  let pc = points(pc_sequential)
  assert_eq(pc.num_points, 12)
  assert_eq(pc.indices.length(), 0)
  assert_eq(summary(pc), [
    (0, 0, 9, 3, false, 144, -596321717),
    (1, 2, 2, 3, true, 36, 401898361),
    (2, 4, 3, 2, false, 48, -1253112131),
  ])
}

///|
test "decode_point_cloud: sequential, floats as they are" {
  let pc = points(pc_raw)
  assert_eq(pc.num_points, 3)
  assert_eq(summary(pc), [(0, 0, 9, 3, false, 36, -1553373210)])
}

///|
test "decode_point_cloud: kd-tree at level 6 (axes chosen, folded rANS numbers), signed values" {
  let pc = points(pc_kd6)
  assert_eq(pc.num_points, 12)
  assert_eq(summary(pc), [
    (0, 0, 9, 3, false, 144, 627193287),
    (1, 2, 2, 3, true, 36, 2101458285),
    (2, 4, 3, 2, false, 48, 822201229),
  ])
}

///|
test "decode_point_cloud: kd-tree at level 0 (direct bits), dequantized positions" {
  let pc = points(pc_kd0)
  assert_eq(summary(pc), [
    (0, 0, 9, 3, false, 144, 1910681098),
    (1, 2, 2, 3, true, 36, 227974097),
  ])
}

///|
test "decode_point_cloud: kd-trees at levels 3 and 0 give the same uint32 points" {
  let a = points(pc_kd3_u32)
  let b = points(pc_kd0_u32)
  assert_eq(summary(a), [(0, 0, 6, 3, false, 144, 1602985254)])
  assert_eq(summary(b), summary(a))
}

///|
test "decode_point_cloud: the float kd-tree of bitstream 2.2" {
  assert_eq(summary(points(pc_legacy_float)), [
    (0, 0, 9, 3, false, 144, 1677443379),
  ])
}

///|
test "decode: a mesh or a point cloud, as the header says" {
  let mesh = hex(standard)
  let pc = hex(pc_kd6)
  assert_true(
    @draco.decode(mesh, 0, mesh.length()) is Some({ indices, .. }) &&
    indices.length() == 24,
  )
  assert_eq(
    summary(@draco.decode(pc, 0, pc.length()).unwrap()),
    summary(points(pc_kd6)),
  )
  assert_true(@draco.decode_mesh(pc, 0, pc.length()) is None)
  assert_true(@draco.decode_point_cloud(mesh, 0, mesh.length()) is None)
}

///|
test "decode_point_cloud: bitstream 2.3 is a point cloud's alone, 2.4 and 1.x nobody's" {
  let pc = hex(pc_sequential)
  pc[6] = b'\x04'
  assert_true(@draco.decode(pc, 0, pc.length()) is None)
  pc[5] = b'\x01'
  pc[6] = b'\x03'
  assert_true(@draco.decode(pc, 0, pc.length()) is None)
  let mesh = hex(standard)
  mesh[6] = b'\x03'
  assert_true(@draco.decode(mesh, 0, mesh.length()) is None)
}

///|
test "decode_point_cloud: refuses every truncated copy" {
  for s in [pc_sequential, pc_kd6, pc_kd0, pc_legacy_float] {
    let src = hex(s)
    for n in 0..<src.length() {
      assert_true(@draco.decode_point_cloud(src, 0, n) is None)
    }
  }
}

///|
test "decode_point_cloud: corrupted copies never trap" {
  let mut seed = 7
  for s in [pc_sequential, pc_kd6, pc_kd0, pc_kd3_u32, pc_legacy_float] {
    let src = hex(s)
    for _ in 0..<300 {
      let copy = src.copy()
      for _ in 0..<3 {
        seed = seed * 1103515245 + 12345
        let at = (seed.reinterpret_as_uint() >> 8).reinterpret_as_int() %
          copy.length()
        copy[at] = (seed >> 3).to_byte()
      }
      let _ = @draco.decode(copy, 0, copy.length())
    }
  }
}

///|
/// A point cloud of bitstream 2.2 with one kd-tree attributes decoder of `descriptor` (count,
/// then type, data type, components, normalized and unique id per attribute) and `body`.
fn legacy_cloud(
  num_points : Int32,
  descriptor : Array[Int32],
  body : Array[Int32],
) -> FixedArray[Byte] {
  let bytes = [68, 82, 65, 67, 79, 2, 2, 0, 1, 0, 0]
  for k in 0..<4 {
    bytes.push((num_points >> (8 * k)) & 0xff)
  }
  bytes.push(1)
  bytes.append(descriptor)
  bytes.append(body)
  FixedArray::makei(bytes.length(), i => bytes[i].to_byte())
}

///|
fn le32(v : Int32) -> Array[Int32] {
  [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]
}

///|
/// Four direct bit decoders of one zero word each.
let empty_direct : Array[Int32] = [
  4, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0,
  0, 0, 0, 0, 0,
]

///|
test "decode_point_cloud: a legacy kd-tree of 2^32 - 1 points at its last level stays quick" {
  let body = [1, 0] + le32(4) + le32(0) + le32(-1) + empty_direct
  let src = legacy_cloud(4, [1, 0, 6, 1, 0, 0], body)
  let pc = @draco.decode_point_cloud(src, 0, src.length()).unwrap()
  assert_eq(pc.num_points, 4)
  assert_eq(pc.attributes[0].data, FixedArray::make(16, b'\x00'))
}

///|
test "decode_point_cloud: refuses kd-trees past 32 bits, past MAX_KD_DIMENSIONS and of other types" {
  let deep = legacy_cloud(
    1,
    [1, 0, 6, 1, 0, 0],
    [1, 0] + le32(1) + le32(33) + le32(1) + empty_direct,
  )
  assert_true(@draco.decode_point_cloud(deep, 0, deep.length()) is None)
  let descriptor = [5]
  for i in 0..<5 {
    descriptor.append([4, 2, 255, 0, i])
  }
  let wide = legacy_cloud(
    1,
    descriptor,
    [1, 0] + le32(1) + le32(0) + le32(1) + empty_direct,
  )
  assert_true(5 * 255 > @draco.MAX_KD_DIMENSIONS)
  assert_true(@draco.decode_point_cloud(wide, 0, wide.length()) is None)
  let doubles = legacy_cloud(
    1,
    [1, 4, 10, 1, 0, 0],
    [1, 0] + le32(1) + le32(0) + le32(1) + empty_direct,
  )
  assert_true(@draco.decode_point_cloud(doubles, 0, doubles.length()) is None)
}

///|
test "decode_point_cloud: refuses legacy attributes sized past MAX_POINTS and negative counts" {
  let big = legacy_cloud(
    1,
    [1, 0, 6, 1, 0, 0],
    [1, 0] + le32(@draco.MAX_POINTS + 1) + le32(0) + le32(1) + empty_direct,
  )
  assert_true(@draco.decode_point_cloud(big, 0, big.length()) is None)
  let src = hex(pc_raw)
  src[14] = b'\xff'
  assert_true(@draco.decode_point_cloud(src, 0, src.length()) is None)
}

///|
test "DracoMesh::to_bytes: a point cloud has no indices" {
  let out = points(pc_raw).to_bytes()
  assert_eq(out.length(), 12 + 12 + 36)
  assert_eq([out[0], out[1], out[2], out[3], out[4]], [
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x03',
  ])
}
