// The host's `Number(string)`, `String(number)` and `Intl` for expressions in the
// wasm-gc entries (`host.mjs` `hostText`); the display worker keeps its own copy, as
// an all-targets package cannot import this one.

///|
fn host_text_char(c : Int32) = "host" "text_char"

///|
fn host_text_number() -> Double = "host" "text_number"

///|
fn host_number_text(x : Double) -> Int32 = "host" "number_text"

///|
fn host_text_code(i : Int32) -> Int32 = "host" "text_code"

///|
fn host_intl(
  op : Int32,
  flags : Int32,
  x : Double,
  y : Double,
  z : Double,
  la : Int32,
  lb : Int32,
) -> Double = "host" "intl"

///|
/// Appends `s` (if any) to the host's text and returns its length.
fn host_arg(s : String?) -> Int32 {
  guard s is Some(s) else { return 0 }
  for i in 0..<s.length() {
    host_text_char(s[i].to_int())
  }
  s.length()
}

///|
/// The host's text result of `n` code units, None where `Intl` threw (-1).
fn host_result(n : Double) -> String? {
  guard n >= 0.0 else { return None }
  let out = StringBuilder()
  for i in 0..<n.to_int() {
    out.write_char(host_text_code(i).unsafe_to_char())
  }
  Some(out.to_string())
}

///|
fn bit(given : Bool, b : Int32) -> Int32 {
  if given {
    b
  } else {
    0
  }
}

///|
/// The host's `Number(s)`.
pub fn host_text_to_number(s : String) -> Double {
  host_arg(Some(s)) |> ignore
  host_text_number()
}

///|
/// The host's `String(x)`, which keeps MoonBit's float printing out of the module.
pub fn host_number_to_text(x : Double) -> String {
  host_result(host_number_text(x).to_double()).unwrap_or("")
}

///|
/// MapLibre's `number-format` by the host's `Intl.NumberFormat`; None where it throws.
pub fn host_number_format(
  x : Double,
  locale : String?,
  currency : String?,
  unit : String?,
  min : Double?,
  max : Double?,
) -> String? {
  let la = host_arg(locale)
  let lb = host_arg(currency)
  host_arg(unit) |> ignore
  let flags = bit(locale is Some(_), 1) |
    bit(currency is Some(_), 2) |
    bit(unit is Some(_), 4) |
    bit(min is Some(_), 8) |
    bit(max is Some(_), 16)
  host_result(
    host_intl(0, flags, x, min.unwrap_or(0.0), max.unwrap_or(0.0), la, lb),
  )
}

///|
/// A collator's comparison by the host's `Intl.Collator`; NaN where it throws.
pub fn host_collate(
  a : String,
  b : String,
  case : Bool,
  diacritic : Bool,
  locale : String?,
) -> Double {
  let la = host_arg(Some(a))
  let lb = host_arg(Some(b))
  host_arg(locale) |> ignore
  let flags = bit(case, 1) | bit(diacritic, 2) | bit(locale is Some(_), 4)
  host_intl(1, flags, 0.0, 0.0, 0.0, la, lb)
}

///|
/// A collator's resolved locale by the host's `Intl.Collator`.
pub fn host_resolved_locale(locale : String?) -> String? {
  let la = host_arg(locale)
  host_result(host_intl(2, bit(locale is Some(_), 1), 0.0, 0.0, 0.0, la, 0))
}
