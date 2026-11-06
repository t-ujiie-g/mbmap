///|
/// Malformed protobuf input. `pos` is the absolute byte offset in the buffer.
#derive(Debug, Eq)
pub(all) suberror PbfError {
  UnexpectedEof(pos~ : Int32)
  VarintTooLong(pos~ : Int32)
  UnsupportedWireType(pos~ : Int32, Int32)
  LengthOutOfRange(pos~ : Int32, Int32)
}
