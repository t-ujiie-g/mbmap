///|
pub const WIRE_VARINT : Int32 = 0

///|
pub const WIRE_FIXED64 : Int32 = 1

///|
pub const WIRE_LEN : Int32 = 2

///|
pub const WIRE_FIXED32 : Int32 = 5

///|
/// Encodes a field tag, e.g. for matching: `tag(3, WIRE_LEN)`.
pub fn tag(field : Int32, wire : Int32) -> Int32 {
  (field << 3) | wire
}
