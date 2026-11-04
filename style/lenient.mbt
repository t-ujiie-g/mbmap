///|
/// Properties of the Style Spec that are not drawn yet: a style using them
/// is drawn without them, with a warning.
let ignored_properties : Array[String] = [
  "fill-sort-key", "line-sort-key", "circle-sort-key", "symbol-avoid-edges", "symbol-z-order",
]

///|
/// What a style uses that cannot be drawn. Strict, the first one raises;
/// otherwise each is kept in `warnings` and the style is drawn without it.
priv struct Issues {
  strict : Bool
  warnings : Array[StyleError]
}

///|
fn Issues::report(self : Issues, e : StyleError) -> Unit raise StyleError {
  if self.strict {
    raise e
  }
  self.warnings.push(e)
}

///|
/// `json` without `section.key` (or without `key` when `section` is empty).
fn without_key(json : Json, section : String, key : String) -> Json {
  guard json is Object(o) else { return json }
  let out : Map[String, Json] = Map([])
  for k, v in o {
    if section == "" {
      if k != key {
        out[k] = v
      }
    } else if k == section {
      out[k] = without_key(v, "", key)
    } else {
      out[k] = v
    }
  }
  Json::object(out)
}

///|
/// Where in an object at `prefix` an issue at `path` lies: the section
/// (`paint`, `layout` or empty for the object itself) and the key, or None
/// when it is the object as a whole or something that cannot be left out.
fn removable(path : String, prefix : String) -> (String, String)? {
  guard path.has_prefix(prefix + ".") else { return None }
  let start = prefix.length() + 1
  let first = name_end(path, start)
  let head = path.unsafe_substring(start~, end=first)
  if head is ("paint" | "layout") {
    guard first < path.length() && path[first] == '.' else { return None }
    let end = name_end(path, first + 1)
    return Some((head, path.unsafe_substring(start=first + 1, end~)))
  }
  if head is ("filter" | "type" | "source" | "source-layer") {
    return None
  }
  Some(("", head))
}

///|
/// Where the property name starting at `start` in `path` ends.
fn name_end(path : String, start : Int32) -> Int32 {
  let mut i = start
  while i < path.length() && path[i] != '.' && path[i] != '[' {
    i += 1
  }
  i
}

///|
/// Parses `json` with `parse`; an unsupported property is left out and parsing
/// tried again, anything else unsupported drops the whole (None). Invalid
/// values always raise.
fn[T] leniently(
  json : Json,
  prefix : String,
  issues : Issues,
  parse : (Json) -> T? raise StyleError,
) -> T? raise StyleError {
  let mut json = json
  for _ in 0..<MAX_LENIENT_TRIES {
    try parse(json) catch {
      Unsupported(path~, _) as e => {
        issues.report(e)
        match removable(path, prefix) {
          Some((section, key)) => json = without_key(json, section, key)
          None => return None
        }
      }
      e => raise e
    } noraise {
      v => return v
    }
  }
  None
}

///|
/// How many unsupported properties of one layer or source are left out before
/// it is dropped instead.
const MAX_LENIENT_TRIES : Int32 = 64

///|
/// Adds to `warnings` the properties of `json`'s drawn layers that are parsed
/// but not drawn yet (strict, raises the first). Only the main thread reports,
/// so the display worker leaves this out.
pub fn Style::report_ignored(
  self : Style,
  json : Json,
  strict~ : Bool = true,
) -> Unit raise StyleError {
  guard json is Object(root) && root.get("layers") is Some(Array(list)) else {
    return
  }
  let issues = { strict, warnings: self.warnings, }
  for i, layer in list {
    guard layer is Object(l) &&
      l.get("id") is Some(String(id)) &&
      self.layers.iter().any(d => d.id == id) else {
      continue
    }
    for section in ["paint", "layout"] {
      guard l.get(section) is Some(Object(props)) else { continue }
      for key, _ in props {
        if ignored_properties.contains(key) {
          issues.report(
            Unsupported(path="layers[\{i}].\{section}.\{key}", "not drawn yet"),
          )
        }
      }
    }
  }
}
