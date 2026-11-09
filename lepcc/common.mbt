// Ported from Esri's LEPCC (src/Common.cpp, src/lepcc_c_api_impl.cpp and the blob headers of
// src/LEPCC.h, src/ClusterRGB.h, src/Intensity.h, src/FlagBytes.h): Apache License 2.0,
// Copyright 2016 Esri. See NOTICE.

///|
/// The most points (colors, intensities) a blob may hold, and the most values any of its
/// bit-stuffed arrays may unpack to.
pub const MAX_POINTS : Int32 = 0x400000

///|
/// What a blob holds, as `lepcc_getBlobInfo` names it (`BlobType`).
#derive(Eq)
pub(all) enum BlobType {
  Xyz
  Rgb
  Intensity
  FlagBytes
}

///|
/// The 10-byte file keys of each blob type, in `BlobType`'s order.
let file_keys : FixedArray[String] = [
  "LEPCC     ", "ClusterRGB", "Intensity ", "FlagBytes ",
]

///|
/// `sizeof(TopHeader)`: the file key, a u16 version and a u32 checksum.
const TOP_HEADER_SIZE : Int32 = 16

///|
/// The newest blob version each decoder reads (`kCurrVersion`).
const CURRENT_VERSION : Int32 = 1

///|
fn u8_at(data : FixedArray[Byte], at : Int32) -> Int32 {
  data[at].to_int()
}

///|
fn u16_at(data : FixedArray[Byte], at : Int32) -> Int32 {
  data[at].to_int() | (data[at + 1].to_int() << 8)
}

///|
fn u32_at(data : FixedArray[Byte], at : Int32) -> UInt32 {
  (data[at].to_int() |
  (data[at + 1].to_int() << 8) |
  (data[at + 2].to_int() << 16) |
  (data[at + 3].to_int() << 24)).reinterpret_as_uint()
}

///|
fn i64_at(data : FixedArray[Byte], at : Int32) -> Int64 {
  u32_at(data, at).to_uint64().reinterpret_as_int64() |
  (u32_at(data, at + 4).to_uint64() << 32).reinterpret_as_int64()
}

///|
fn f64_at(data : FixedArray[Byte], at : Int32) -> Double {
  i64_at(data, at).reinterpret_as_double()
}

///|
fn has_key(data : FixedArray[Byte], start : Int32, kind : BlobType) -> Bool {
  let key = file_keys[kind_index(kind)]
  for i in 0..<10 {
    guard data[start + i].to_int() == key.code_unit_at(i).to_int() else {
      return false
    }
  }
  true
}

///|
fn kind_index(kind : BlobType) -> Int32 {
  match kind {
    Xyz => 0
    Rgb => 1
    Intensity => 2
    FlagBytes => 3
  }
}

///|
/// `Common::ComputeChecksumFletcher32` of `data[start, start + len)`.
fn fletcher32(data : FixedArray[Byte], start : Int32, len : Int32) -> UInt32 {
  let mut sum1 = 0xffffU
  let mut sum2 = 0xffffU
  let mut words = len / 2
  let mut p = start
  while words > 0 {
    let tlen = if words >= 359 { 359 } else { words }
    words -= tlen
    for _ in 0..<tlen {
      sum1 += data[p].to_uint() << 8
      sum1 += data[p + 1].to_uint()
      sum2 += sum1
      p += 2
    }
    sum1 = (sum1 & 0xffffU) + (sum1 >> 16)
    sum2 = (sum2 & 0xffffU) + (sum2 >> 16)
  }
  if (len & 1) != 0 {
    sum1 += data[p].to_uint() << 8
    sum2 += sum1
  }
  sum1 = (sum1 & 0xffffU) + (sum1 >> 16)
  sum2 = (sum2 & 0xffffU) + (sum2 >> 16)
  (sum2 << 16) | sum1
}

///|
/// Checks what each decoder's `ReadHeaders` and `Decode` check before the payload: the key, the
/// version, a blob that fits in `len` bytes and its checksum. Returns the blob's size, or -1.
/// A blob shorter than its headers is refused here: the C++ checksums it with a wrapped length.
fn check_blob(
  data : FixedArray[Byte],
  start : Int32,
  len : Int32,
  kind : BlobType,
  header_size : Int32,
) -> Int32 {
  guard start >= 0 &&
    len > header_size &&
    start.to_int64() + len.to_int64() <= data.length().to_int64() &&
    has_key(data, start, kind) &&
    u16_at(data, start + 10) <= CURRENT_VERSION else {
    return -1
  }
  let blob_size = i64_at(data, start + TOP_HEADER_SIZE)
  guard blob_size <= len.to_int64() && blob_size >= header_size.to_int64() else {
    return -1
  }
  let size = blob_size.to_int()
  guard fletcher32(data, start + TOP_HEADER_SIZE, size - TOP_HEADER_SIZE) ==
    u32_at(data, start + 12) else {
    return -1
  }
  size
}
