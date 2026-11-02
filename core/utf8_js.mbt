///|
/// On the js backend `@utf8.decode_lossy` is the host's TextDecoder.
fn decode_lossy(b : BytesView) -> String {
  @utf8.decode_lossy(b)
}
