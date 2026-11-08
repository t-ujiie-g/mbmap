// Encoded by draco3d 1.5.7's encoder from small grids; the expected indices, point counts and
// attribute values (by FNV-1a hash) are what draco3d 1.5.7's decoder gives.

///|
fn hex(s : String) -> FixedArray[Byte] {
  let digit = fn(c : Char) {
    let v = c.to_int()
    if v <= '9'.to_int() {
      v - '0'.to_int()
    } else {
      v - 'a'.to_int() + 10
    }
  }
  let chars = s.to_array()
  FixedArray::makei(chars.length() / 2, fn(i) {
    ((digit(chars[2 * i]) << 4) | digit(chars[2 * i + 1])).to_byte()
  })
}

///|
fn fnv(data : FixedArray[Byte]) -> Int32 {
  let mut h = 0x811c9dc5
  for b in data {
    h = (h ^ b.to_int()) * 0x01000193
  }
  h
}

///|
/// Each attribute as (unique id, type, data type, components, normalized, bytes, hash).
fn summary(
  mesh : @draco.DracoMesh,
) -> Array[(Int32, Int32, Int32, Int32, Bool, Int32, Int32)] {
  mesh.attributes.map(a => {
    (
      a.unique_id,
      a.attribute_type,
      a.data_type,
      a.num_components,
      a.normalized,
      a.data.length(),
      fnv(a.data),
    )
  })
}

///|
let standard : String = "445241434f0202010100000009080208010003efd31aff0111ff028840ff02884003ff0000000000010000010009030000020101090300010301030902000202010101000c03390e23c931031e5d9effffffffffefffff03a0ff00004000fe0f0000e0ff000080ff010000f41f00000000ff070000000000000000000000000000000000400b000301000803e538131d07033d1e85422f0000ff0000007f00000008010101000b03ad2a1f5515032a624cffffffbfff00f42f0000000000ff03000000000000000000000000803f0a"

///|
let valence : String = "445241434f0202010100000014180218020008effab4aa4fb5aa06ff0111ff02fb41ff02fb4103ff0001000000010000010009030000020101090300010301030902000202010101000f0301102b99196916061039bf775ea3ffffff0f00faffffffff0100001000100000000010000080ff0f010000f8ff030000f8ff002000fc7f40000000fe7f000000f8ff010000f8ff000000f0ff038000f0ff010000f8ff000000e0ff0300000000ff3f0000000000000000000000000000000080400e060301000b17350303350301109929066ce17649688127c4ce3588bd41a4b5afdffee253844020de846322fb792cfe35ce444713fbe82e97463be913836f95ff84c141a53101ff030000ff010000b304273bc6620a050101000d036906136906039909cd0c351399090979998c5db595225f80ffbfaafe97aa5b620d007767752af703804facfa7f6f400155ad222b0039030080f3d2acd700540dc0dd01986a0700120000000e03fad78200000000ff0f000000000000000000000000803f0c"

///|
let sequential : String = "445241434f0202010000000406010001030104030102040205040103000903000002020401010403020002020101000101010280028d23039103ffffffebad0a390e0649d549ca528800000000ff0000000001010102df01ad02ff23ad02ff23ad022f0118d3511d17ad020862bc8d672902908200000000e4000000000101000e2f5535ad0a03f82f836ff7f3813ee8833ee8833ee8833ee8833ee80348f4ffff401f00000000000000000000000000000000004008"

///|
let raw_floats : String = "445241434f02020100000002040100010201030201020009030000040901000100000000000000000000000000000000803f0000000000000000000000000000803f000000000000803f0000803f0000803f000080bf000040bf000000bf000080be"

///|
let metadata : String = "445241434f0202010100800002036c6f640402000000046e616d650474696c650000060400040000025f07ff011101ff000002000903000003090200010202010101000a0301201b012003007090fadfff3f00fffe0120c07f0000000000ff010000010101000a03ad2a1b55150347658a06e80fc03f0200000000ff010000000000000000000000000000000000400900000000000000000000803f09"

///|
fn decoded(s : String) -> @draco.DracoMesh {
  let src = hex(s)
  @draco.decode_mesh(src, 0, src.length()).unwrap()
}

///|
test "decode_mesh: standard edgebreaker, quantized positions, normals and tex coords" {
  let mesh = decoded(standard)
  assert_eq(mesh.num_points, 9)
  assert_eq(mesh.indices, [
    0, 1, 2, 2, 1, 3, 4, 3, 5, 3, 1, 5, 5, 1, 6, 6, 1, 7, 1, 0, 7, 0, 8, 7,
  ])
  assert_eq(summary(mesh), [
    (0, 0, 9, 3, false, 108, -1322209099),
    (1, 1, 9, 3, false, 108, -572824869),
    (2, 3, 9, 2, false, 72, -1798966427),
  ])
}

///|
test "decode_mesh: valence edgebreaker with constrained, geometric normal and tex coords predictions" {
  let mesh = decoded(valence)
  assert_eq(mesh.num_points, 20)
  assert_eq(mesh.indices.length(), 72)
  assert_eq(Array::makei(12, i => mesh.indices[i]), [
    0, 1, 2, 2, 1, 3, 1, 4, 3, 3, 4, 5,
  ])
  assert_eq(summary(mesh), [
    (0, 0, 9, 3, false, 240, -1199455593),
    (1, 1, 9, 3, false, 240, -1855420923),
    (2, 3, 9, 2, false, 160, -1273314833),
  ])
}

///|
test "decode_mesh: sequential mesh with integer attributes" {
  let mesh = decoded(sequential)
  assert_eq(mesh.num_points, 6)
  assert_eq(mesh.indices, [0, 1, 3, 1, 4, 3, 1, 2, 4, 2, 5, 4])
  assert_eq(summary(mesh), [
    (0, 0, 9, 3, false, 72, 259349477),
    (1, 2, 2, 4, true, 24, -334435971),
    (2, 4, 3, 2, false, 24, -418666443),
  ])
}

///|
test "decode_mesh: sequential mesh with raw indices and unquantized floats" {
  let mesh = decoded(raw_floats)
  assert_eq(mesh.indices, [0, 1, 2, 1, 3, 2])
  let floats = fn(a : @draco.DracoAttribute) {
    Array::makei(a.data.length() / 4, fn(i) {
      Float::reinterpret_from_int(
        a.data[4 * i].to_int() |
        (a.data[4 * i + 1].to_int() << 8) |
        (a.data[4 * i + 2].to_int() << 16) |
        (a.data[4 * i + 3].to_int() << 24),
      )
    })
  }
  assert_eq(floats(mesh.attributes[0]), [
    0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0,
  ])
  assert_eq(floats(mesh.attributes[1]), [-1.0, -0.75, -0.5, -0.25])
}

///|
test "decode_mesh: skips the geometry metadata" {
  let mesh = decoded(metadata)
  assert_eq(mesh.num_points, 6)
  assert_eq(mesh.indices, [0, 1, 2, 1, 3, 2, 2, 3, 4, 3, 5, 4])
  assert_eq(summary(mesh), [
    (0, 0, 9, 3, false, 72, -305152363),
    (1, 3, 9, 2, false, 48, 1980800152),
  ])
}

///|
test "decode_mesh: reads the bytes at offset" {
  let src = hex(standard)
  let padded = FixedArray::make(src.length() + 7, b'\xff')
  for i, b in src {
    padded[3 + i] = b
  }
  let mesh = @draco.decode_mesh(padded, 3, src.length()).unwrap()
  assert_eq(summary(mesh), summary(decoded(standard)))
  assert_true(@draco.decode_mesh(padded, 3, src.length() + 4) is Some(_))
  assert_true(@draco.decode_mesh(padded, -1, 4) is None)
  assert_true(@draco.decode_mesh(padded, 3, src.length() + 5) is None)
  assert_true(@draco.decode_mesh(padded, 0, -1) is None)
}

///|
test "decode_mesh: refuses every truncated copy" {
  for s in [standard, valence, sequential, raw_floats, metadata] {
    let src = hex(s)
    for n in 0..<src.length() {
      assert_true(@draco.decode_mesh(src, 0, n) is None)
    }
  }
}

///|
test "decode_mesh: refuses other magic, versions, geometry types and methods" {
  let cases = [
    (0, b'E'),
    (5, b'\x01'),
    (5, b'\x03'),
    (6, b'\x03'),
    (7, b'\x00'),
    (8, b'\x02'),
    (11, b'\x03'),
  ]
  for c in cases {
    let src = hex(standard)
    src[c.0] = c.1
    assert_true(@draco.decode_mesh(src, 0, src.length()) is None)
  }
}

///|
test "decode_mesh: corrupted copies never trap" {
  for s in [standard, valence, sequential, metadata] {
    let src = hex(s)
    for i in 0..<src.length() {
      for bit in [0, 3, 7] {
        let copy = src.copy()
        copy[i] = (copy[i].to_int() ^ (1 << bit)).to_byte()
        match @draco.decode_mesh(copy, 0, copy.length()) {
          Some(mesh) => assert_true(mesh.indices.length() % 3 == 0)
          None => ()
        }
      }
    }
  }
}

///|
test "DracoMesh::attribute: the first attribute of a unique id" {
  let mesh = decoded(sequential)
  assert_eq(mesh.attribute(2).map(a => a.attribute_type), Some(4))
  assert_eq(mesh.attribute(0).map(a => a.num_components), Some(3))
  assert_true(mesh.attribute(3) is None)
}

///|
test "DracoMesh::to_bytes: header, attribute rows, indices, then padded data" {
  let mesh = decoded(sequential)
  let out = mesh.to_bytes()
  let u32 = fn(at : Int32) {
    out[at].to_int() |
    (out[at + 1].to_int() << 8) |
    (out[at + 2].to_int() << 16) |
    (out[at + 3].to_int() << 24)
  }
  assert_eq((u32(0), u32(4), u32(8)), (4, 6, 3))
  assert_eq(
    (
      u32(24),
      out[28].to_int(),
      out[29].to_int(),
      out[30].to_int(),
      out[31].to_int(),
      u32(32),
    ),
    (1, 2, 2, 4, 1, 24),
  )
  assert_eq(u32(48), 0)
  assert_eq(u32(52), 1)
  assert_eq(out.length(), 48 + 48 + 72 + 24 + 24)
  for i in 0..<24 {
    assert_eq(out[48 + 48 + 72 + i], mesh.attributes[1].data[i])
  }
}
