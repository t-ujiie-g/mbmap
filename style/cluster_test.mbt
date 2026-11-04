///|
/// A context whose `accumulated` is `acc` and whose properties are `props`.
struct Reducing {
  acc : @style.Value
  props : Map[String, @style.Value]
}

///|
impl @style.FeatureContext for Reducing with fn property(self, key) {
  self.props.get(key)
}

///|
impl @style.FeatureContext for Reducing with fn geometry_type(_) {
  "Unknown"
}

///|
impl @style.FeatureContext for Reducing with fn accumulated(self) {
  self.acc
}

///|
test "cluster properties compile an operator's name as a reduce over accumulated" {
  let json = @json.parse(
    (
      #|{"sum": ["+", ["get", "n"]], "names": [["concat", ["accumulated"], ["get", "names"]], ["get", "name"]]}
    ),
  ) catch {
    _ => abort("not JSON")
  }
  let props = @style.compile_cluster_properties(json) catch {
    e => abort(e.message())
  }
  assert_eq(props.map(p => p.0), ["sum", "names"])
  let at = (acc : @style.Value, props : Array[(String, @style.Value)]) => Reducing::{
    acc,
    props: Map::from_array(props),
  }
  assert_eq(props[0].1.eval(0.0, at(Null, [("n", Num(3.0))])), Num(3.0))
  assert_eq(props[0].2.eval(0.0, at(Num(4.0), [("sum", Num(3.0))])), Num(7.0))
  assert_eq(
    props[1].2.eval(0.0, at(Str("a"), [("names", Str("b"))])),
    Str("ab"),
  )
  // Elsewhere `accumulated` is null.
  assert_eq(@style.Accumulated.eval(0.0, @style.NoFeature::{ }), Null)
  let bytes = @style.write_cluster_properties(props)
  assert_eq(@style.read_cluster_properties(bytes[:]), Some(props))
  assert_eq(@style.read_cluster_properties(bytes[:bytes.length() - 1]), None)
  assert_eq(@style.read_cluster_properties(b"\x01\x00\x00\x00"[:]), None)
}

///|
test "malformed cluster properties are Invalid with their path" {
  for
    bad in [
      ("[]", ""),
      ("{\"a\": 1}", ".a"),
      ("{\"a\": [\"+\"]}", ".a"),
      ("{\"a\": [\"+\", [\"nope\"]]}", ".a[1]"),
    ] {
    let json = @json.parse(bad.0) catch { _ => abort("not JSON") }
    try @style.compile_cluster_properties(json) catch {
      Invalid(path~, _) | Unsupported(path~, _) => assert_eq(path, bad.1)
    } noraise {
      _ => fail("expected an error at \{bad.1}")
    }
  }
}
