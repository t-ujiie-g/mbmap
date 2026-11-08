// Encoded inputs and expected outputs come from meshoptimizer 1.3.0's npm MeshoptEncoder and
// MeshoptDecoder.

///|
fn decoded(
  count : Int32,
  size : Int32,
  source : FixedArray[Byte],
  mode : @meshopt.Mode,
  filter~ : @meshopt.Filter = NoFilter,
) -> FixedArray[Byte]? {
  let target = FixedArray::make(count * size, b'\xff')
  if @meshopt.decode_gltf_buffer(
      target,
      count,
      size,
      source,
      0,
      source.length(),
      mode,
      filter,
    ) {
    Some(target)
  } else {
    None
  }
}

///|
let v0_source : FixedArray[Byte] = [
  160, 1, 42, 0, 0, 0, 1, 63, 0, 0, 0, 4, 4, 4, 1, 21, 0, 0, 0, 1, 8, 0, 0, 0, 1,
  15, 0, 0, 0, 113, 114, 0, 0, 1, 42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 20, 30, 40, 1, 2, 3, 4,
]

///|
let v0_vertices : FixedArray[Byte] = [
  10, 20, 30, 40, 1, 2, 3, 4, 11, 22, 29, 40, 1, 2, 3, 5, 12, 24, 28, 41, 200, 2,
  3, 6, 13, 26, 27, 41, 1, 2, 3, 7,
]

///|
test "decode_gltf_buffer decodes a version 0 vertex stream" {
  assert_eq(decoded(4, 8, v0_source, Attributes), Some(v0_vertices))
}

///|
test "decode_gltf_buffer decodes a version 1 stream with control modes and 16-bit channels" {
  let source : FixedArray[Byte] = [
    161, 191, 153, 255, 0, 82, 0, 215, 213, 215, 213, 101, 235, 235, 235, 233, 235,
    235, 235, 233, 235, 235, 92, 245, 0, 184, 0, 163, 163, 163, 163, 102, 81, 81,
    81, 81, 81, 81, 81, 81, 81, 81, 143, 40, 0, 94, 64, 48, 46, 48, 48, 40, 24, 24,
    24, 24, 24, 22, 24, 24, 24, 24, 18, 12, 2, 6, 102, 102, 102, 102, 102, 102, 102,
    15, 0, 6, 6, 6, 6, 2, 9, 153, 153, 153, 153, 153, 153, 153, 15, 0, 9, 9, 9, 9,
    0, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74,
    0, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74,
    0, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74,
    0, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74, 74,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 192, 63, 232, 3, 96, 234, 88, 99, 110, 121,
    1, 1, 0,
  ]
  let out = decoded(20, 12, source, Attributes).unwrap()
  for i in 0..<20 {
    let o = i * 12
    let f = out[o].to_int() |
      (out[o + 1].to_int() << 8) |
      (out[o + 2].to_int() << 16) |
      (out[o + 3].to_int() << 24)
    assert_eq(
      Float::reinterpret_from_int(f),
      Float::from_double(1.5 + i.to_double() * 0.37),
    )
    assert_eq(out[o + 4].to_int() | (out[o + 5].to_int() << 8), 1000 + i * 3)
    assert_eq(out[o + 6].to_int() | (out[o + 7].to_int() << 8), 60000 - i * 5)
    for k in 8..<12 {
      assert_eq(out[o + k].to_int(), (i * 37 + k * 11) & 0xff)
    }
  }
}

///|
test "decode_gltf_buffer decodes XOR channels" {
  // three vertices of one float lane, channel 2 with rotation 0 written by hand:
  // literal bytes (control 3) of the words XORed with the previous one
  let source : FixedArray[Byte] = FixedArray::make(38, b'\x00')
  let head : FixedArray[Byte] = [0xa1, 0xff, 1, 2, 3, 0, 0, 0, 0, 0, 0, 4, 0, 0]
  let tail : FixedArray[Byte] = [0x10, 0x20, 0x30, 0x40, 2]
  for i in 0..<head.length() {
    source[i] = head[i]
  }
  for i in 0..<tail.length() {
    source[33 + i] = tail[i]
  }
  assert_eq(
    decoded(3, 4, source, Attributes),
    Some([
      0x11, 0x20, 0x30, 0x44, 0x13, 0x20, 0x30, 0x44, 0x10, 0x20, 0x30, 0x44,
    ]),
  )
}

///|
test "decode_gltf_buffer decodes nothing for a count of 0" {
  let source : FixedArray[Byte] = FixedArray::make(25, b'\x00')
  source[0] = b'\xa1'
  assert_eq(decoded(0, 4, source, Attributes), Some([]))
}

///|
test "decode_gltf_buffer decodes 16-bit triangles" {
  let source : FixedArray[Byte] = [
    225, 254, 30, 16, 14, 78, 30, 18, 14, 15, 6, 0, 118, 135, 86, 103, 120, 169,
    134, 101, 137, 104, 152, 1, 105, 0, 0,
  ]
  assert_eq(
    decoded(24, 2, source, Triangles),
    Some([
      0, 0, 1, 0, 3, 0, 3, 0, 1, 0, 4, 0, 4, 0, 1, 0, 2, 0, 4, 0, 2, 0, 5, 0, 3,
      0, 4, 0, 6, 0, 6, 0, 4, 0, 7, 0, 7, 0, 4, 0, 5, 0, 7, 0, 5, 0, 8, 0,
    ]),
  )
}

///|
test "decode_gltf_buffer decodes 32-bit triangles with free indices" {
  let source : FixedArray[Byte] = [
    225, 255, 31, 255, 255, 192, 154, 12, 181, 154, 12, 214, 197, 8, 221, 197, 8,
    79, 16, 238, 255, 255, 255, 7, 0, 118, 135, 86, 103, 120, 169, 134, 101, 137,
    104, 152, 1, 105, 0, 0,
  ]
  assert_eq(
    decoded(9, 4, source, Triangles),
    Some([
      160, 134, 1, 0, 5, 0, 0, 0, 112, 17, 1, 0, 112, 17, 1, 0, 5, 0, 0, 0, 1, 0,
      0, 0, 9, 0, 0, 0, 160, 134, 1, 0, 0, 0, 0, 64,
    ]),
  )
}

///|
test "decode_gltf_buffer decodes index sequences of both widths" {
  let seq32 : FixedArray[Byte] = [
    209, 0, 4, 4, 0, 2, 8, 255, 191, 205, 178, 4, 16, 14, 2, 0, 0, 0, 0,
  ]
  assert_eq(
    decoded(10, 4, seq32, Indices),
    Some([
      0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0, 0,
      40, 107, 238, 7, 0, 0, 0, 3, 0, 0, 0, 2, 0, 0, 0,
    ]),
  )
  let seq16 : FixedArray[Byte] = [209, 20, 6, 253, 255, 15, 10, 36, 0, 0, 0, 0]
  assert_eq(
    decoded(5, 2, seq16, Indices),
    Some([5, 0, 3, 0, 255, 255, 0, 0, 9, 0]),
  )
}

///|
test "decode_gltf_buffer applies the octahedral filter to both widths" {
  let oct4 : FixedArray[Byte] = [
    161, 175, 0, 108, 214, 190, 0, 145, 59, 206, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 0, 0,
  ]
  assert_eq(
    decoded(4, 4, oct4, Attributes, filter=Octahedral),
    Some([0, 0, 127, 0, 76, 154, 0, 0, 219, 206, 145, 0, 0, 0, 127, 0]),
  )
  let oct8 : FixedArray[Byte] = [
    161, 255, 170, 0, 218, 193, 23, 0, 6, 17, 12, 0, 220, 54, 238, 0, 9, 3, 14, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 7, 0, 0, 0, 0,
  ]
  assert_eq(
    decoded(4, 8, oct8, Attributes, filter=Octahedral),
    Some([
      0, 0, 0, 0, 255, 127, 0, 0, 197, 76, 149, 153, 0, 0, 0, 0, 157, 217, 202, 204,
      39, 145, 0, 0, 0, 0, 0, 0, 255, 127, 0, 0,
    ]),
  )
}

///|
test "decode_gltf_buffer applies the quaternion filter" {
  let source : FixedArray[Byte] = [
    161, 255, 191, 0, 177, 178, 0, 10, 9, 0, 177, 178, 0, 10, 9, 0, 177, 180, 0,
    10, 25, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    255, 7, 0, 0,
  ]
  assert_eq(
    decoded(3, 8, source, Attributes, filter=Quaternion),
    Some([
      0, 0, 0, 0, 0, 0, 255, 127, 15, 64, 250, 63, 250, 63, 250, 63, 130, 90, 0,
      0, 0, 0, 126, 165,
    ]),
  )
}

///|
test "decode_gltf_buffer applies the exponential filter" {
  let source : FixedArray[Byte] = [
    161, 174, 255, 255, 0, 95, 0, 3, 0, 160, 0, 2, 0, 113, 0, 81, 0, 231, 0, 1, 0,
    36, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 243, 59, 223, 255, 233, 72, 60, 0, 3,
    0, 0, 0,
  ]
  assert_eq(
    decoded(2, 12, source, Attributes, filter=Exponential),
    Some([
      0, 0, 192, 63, 0, 20, 131, 186, 0, 32, 241, 71, 0, 0, 0, 0, 0, 228, 60, 30,
      0, 132, 223, 208,
    ]),
  )
}

///|
test "decode_gltf_buffer writes a canonical NaN for exponent -128 times 0" {
  // one word 0x80000000: literal bytes on a XOR channel
  let source : FixedArray[Byte] = FixedArray::make(30, b'\x00')
  source[0] = b'\xa1'
  source[1] = b'\xff'
  source[5] = b'\x80'
  source[29] = b'\x02'
  assert_eq(
    decoded(1, 4, source, Attributes, filter=Exponential),
    Some([0, 0, 0xc0, 0x7f]),
  )
}

///|
test "decode_gltf_buffer applies the color filter to both widths" {
  let color4 : FixedArray[Byte] = [
    161, 255, 0, 76, 203, 0, 156, 102, 0, 126, 0, 0, 125, 127, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 127, 193, 255, 0,
  ]
  assert_eq(
    decoded(3, 4, color4, Attributes, filter=Color),
    Some([254, 1, 0, 255, 51, 102, 153, 128, 0, 0, 0, 0]),
  )
  let color8 : FixedArray[Byte] = [
    161, 255, 255, 0, 204, 203, 0, 4, 11, 0, 99, 102, 0, 21, 8, 0, 1, 0, 0, 8, 0,
    0, 2, 0, 0, 5, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 255, 7, 1,
    252, 255, 15, 0, 0,
  ]
  assert_eq(
    decoded(3, 8, color8, Attributes, filter=Color),
    Some([
      239, 255, 16, 0, 0, 0, 255, 255, 51, 51, 102, 102, 153, 153, 8, 128, 0, 0,
      0, 0, 0, 0, 0, 0,
    ]),
  )
}

///|
test "decode_gltf_buffer reads a slice of a larger buffer" {
  let source = FixedArray::make(v0_source.length() + 7, b'\x55')
  for i in 0..<v0_source.length() {
    source[3 + i] = v0_source[i]
  }
  let target = FixedArray::make(32, b'\x00')
  assert_true(
    @meshopt.decode_gltf_buffer(
      target,
      4,
      8,
      source,
      3,
      v0_source.length(),
      Attributes,
      NoFilter,
    ),
  )
  assert_eq(target, v0_vertices)
}

///|
test "decode_gltf_buffer refuses truncated, padded and mislabelled input" {
  let cut = FixedArray::make(v0_source.length() - 1, b'\x00')
  for i in 0..<cut.length() {
    cut[i] = v0_source[i]
  }
  assert_eq(decoded(4, 8, cut, Attributes), None)
  let padded = FixedArray::make(v0_source.length() + 1, b'\x00')
  for i in 0..<v0_source.length() {
    padded[i] = v0_source[i]
  }
  assert_eq(decoded(4, 8, padded, Attributes), None)
  assert_eq(decoded(0, 8, v0_source, Attributes), None)
  assert_eq(decoded(65, 8, v0_source, Attributes), None)
  assert_true(decoded(64, 8, v0_source, Attributes) is Some(_))
  assert_eq(decoded(4, 8, [], Attributes), None)
  assert_eq(decoded(4, 8, v0_source, Triangles), None)
  assert_eq(decoded(4, 8, v0_source, Indices), None)
  let tri : FixedArray[Byte] = [
    225, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ]
  assert_eq(decoded(3, 2, tri, Triangles), None)
  let seq : FixedArray[Byte] = [209, 0, 0, 0, 0]
  assert_eq(decoded(1, 2, seq, Indices), None)
  // a free-index triangle reads past the data, then a second one finds none left
  let free = FixedArray::make(18, b'\x00')
  free[0] = b'\xe1'
  free[1] = b'\xff'
  assert_eq(decoded(3, 2, free, Triangles), None)
  let two = FixedArray::make(19, b'\x00')
  two[0] = b'\xe1'
  two[1] = b'\xff'
  two[2] = b'\xff'
  assert_eq(decoded(6, 2, two, Triangles), None)
  let seq16 : FixedArray[Byte] = [209, 20, 6, 253, 255, 15, 10, 36, 0, 0, 0, 0]
  assert_eq(decoded(6, 2, seq16, Indices), None)
  assert_eq(decoded(4, 2, seq16, Indices), None)
}

///|
test "decode_gltf_buffer refuses unknown headers and versions" {
  let source = v0_source.copy()
  source[0] = b'\xa2'
  assert_eq(decoded(4, 8, source, Attributes), None)
  source[0] = b'\x00'
  assert_eq(decoded(4, 8, source, Attributes), None)
  let tri : FixedArray[Byte] = FixedArray::make(20, b'\x00')
  tri[0] = b'\xe2'
  assert_eq(decoded(3, 2, tri, Triangles), None)
  let seq : FixedArray[Byte] = [0xd2, 0, 0, 0, 0, 0]
  assert_eq(decoded(1, 2, seq, Indices), None)
}

///|
test "decode_gltf_buffer refuses a reserved channel mode" {
  let source : FixedArray[Byte] = FixedArray::make(30, b'\x00')
  source[0] = b'\xa1'
  source[29] = b'\x03'
  assert_eq(decoded(1, 4, source, Attributes), None)
}

///|
test "decode_gltf_buffer refuses sizes and filters the extension does not allow" {
  assert_eq(decoded(4, 6, v0_source, Attributes), None)
  assert_eq(decoded(1, 260, v0_source, Attributes), None)
  assert_eq(decoded(4, 0, v0_source, Attributes), None)
  assert_true(
    decoded(4, 8, v0_source, Attributes, filter=Quaternion) is Some(_),
  )
  assert_eq(decoded(1, 4, v0_source, Attributes, filter=Quaternion), None)
  assert_eq(decoded(1, 12, v0_source, Attributes, filter=Octahedral), None)
  assert_eq(decoded(1, 12, v0_source, Attributes, filter=Color), None)
  assert_eq(decoded(3, 3, v0_source, Triangles), None)
  assert_eq(decoded(4, 2, v0_source, Triangles), None)
  assert_eq(decoded(3, 2, v0_source, Triangles, filter=Exponential), None)
  assert_eq(decoded(3, 2, v0_source, Indices, filter=Octahedral), None)
}

///|
test "decode_gltf_buffer refuses counts and slices out of range" {
  let target = FixedArray::make(31, b'\x00')
  let call = (count, offset, length) => {
    @meshopt.decode_gltf_buffer(
      target,
      count,
      8,
      v0_source,
      offset,
      length,
      Attributes,
      NoFilter,
    )
  }
  assert_false(call(4, 0, v0_source.length()))
  assert_false(call(0x7fffffff, 0, v0_source.length()))
  assert_false(call(-1, 0, v0_source.length()))
  assert_false(call(0, -1, 4))
  assert_false(call(0, 1, v0_source.length()))
  assert_false(call(0, 0, -1))
}

///|
test "Mode::from_string and Filter::from_string read the extension's strings" {
  assert_true(@meshopt.Mode::from_string("ATTRIBUTES") is Some(Attributes))
  assert_true(@meshopt.Mode::from_string("TRIANGLES") is Some(Triangles))
  assert_true(@meshopt.Mode::from_string("INDICES") is Some(Indices))
  assert_true(@meshopt.Mode::from_string("attributes") is None)
  assert_true(@meshopt.Filter::from_string("NONE") is Some(NoFilter))
  assert_true(@meshopt.Filter::from_string("OCTAHEDRAL") is Some(Octahedral))
  assert_true(@meshopt.Filter::from_string("QUATERNION") is Some(Quaternion))
  assert_true(@meshopt.Filter::from_string("EXPONENTIAL") is Some(Exponential))
  assert_true(@meshopt.Filter::from_string("COLOR") is Some(Color))
  assert_true(@meshopt.Filter::from_string("") is None)
}
