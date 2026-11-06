///|
/// A feature property value. `Null` stands for a value message with no field
/// set, which the spec forbids but other decoders accept.
#derive(Debug, Eq)
pub(all) enum Value {
  String(String)
  Float(Float)
  Double(Double)
  Int(Int64)
  UInt(UInt64)
  SInt(Int64)
  Bool(Bool)
  Null
}

///|
fn parse_value(r : @pbf.Reader) -> Value {
  let token = r.enter()
  let mut v = Null
  while !r.at_end() {
    let t = r.read_tag()
    match t {
      VALUE_STRING => v = String(r.read_string())
      VALUE_FLOAT => v = Float(r.read_float())
      VALUE_DOUBLE => v = Double(r.read_double())
      VALUE_INT => v = Int(r.read_int64())
      VALUE_UINT => v = UInt(r.read_varint64())
      VALUE_SINT => v = SInt(r.read_sint64())
      VALUE_BOOL => v = Bool(r.read_bool())
      _ => r.skip(t)
    }
  }
  r.exit(token)
  v
}
