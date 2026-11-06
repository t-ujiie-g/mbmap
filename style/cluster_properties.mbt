///|
/// A GeoJSON source's `clusterProperties` as MapLibre's GeoJSON worker takes them: per
/// key its map expression and reduce expression (an operator's name `op` stands for
/// `[op, ["accumulated"], ["get", key]]`).
pub fn compile_cluster_properties(
  json : Json,
  path~ : String = "",
) -> Array[(String, Expr, Expr)] raise StyleError {
  guard json is Object(o) else { raise Invalid(path~, "not an object") }
  let out = []
  for key, v in o {
    let at = "\{path}.\{key}"
    guard v is Array([operator, map]) else {
      raise Invalid(path=at, "not [operator, map expression]")
    }
    let reduce = match operator {
      String(op) =>
        Json::array([
          Json::string(op),
          Json::array([Json::string("accumulated")]),
          Json::array([Json::string("get"), Json::string(key)]),
        ])
      j => j
    }
    out.push(
      (key, compile(map, path="\{at}[1]"), compile(reduce, path="\{at}[0]")),
    )
  }
  out
}
