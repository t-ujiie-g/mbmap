///|
/// The global state while a style's expressions compile: `global-state`
/// takes its value from here.
let style_state : Ref[Map[String, Json]] = { val: Map([]), }

///|
/// `f()` with `global-state` reading `state` (MapLibre's global state: each
/// key's value), as `Style::from_json` compiles with its style's `state`.
pub fn[T] with_global_state(
  state : Map[String, Json],
  f : () -> T raise StyleError,
) -> T raise StyleError {
  let saved = style_state.val
  style_state.val = state
  defer {
    style_state.val = saved
  }
  f()
}

///|
/// MapLibre's global state of a style: each key of its `state` with its
/// `default` (null without one).
fn state_defaults(json : Json) -> Map[String, Json] {
  let out = Map([])
  if json is Object(root) && root.get("state") is Some(Object(state)) {
    for k, v in state {
      out[k] = match v {
        Object(o) => o.get("default").unwrap_or(Json::null())
        _ => Json::null()
      }
    }
  }
  out
}
