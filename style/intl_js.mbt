///|
/// `Intl.NumberFormat(...).format(x)` as MapLibre's `number-format` calls it;
/// `flags` tell which of locale (1), currency (2), unit (4), min (8) and max
/// (16) are given. NUL where `Intl` throws.
extern "js" fn js_number_format(
  x : Double,
  flags : Int32,
  locale : String,
  currency : String,
  unit : String,
  min : Double,
  max : Double,
) -> String =
  #|(x, f, l, c, u, min, max) => { try { return new Intl.NumberFormat(f & 1 ? l : [], { style: f & 2 ? "currency" : f & 4 ? "unit" : "decimal", currency: f & 2 ? c : undefined, unit: f & 4 ? u : undefined, minimumFractionDigits: f & 8 ? min : undefined, maximumFractionDigits: f & 16 ? max : undefined }).format(x); } catch { return "\0"; } }

///|
/// MapLibre's `Collator.compare` (`sensitivity` from case and diacritic,
/// `usage: "search"`); NaN where `Intl` throws.
extern "js" fn js_collate(
  a : String,
  b : String,
  case : Bool,
  diacritic : Bool,
  has_locale : Bool,
  locale : String,
) -> Double =
  #|(a, b, c, d, h, l) => { try { return new Intl.Collator(h ? l : [], { sensitivity: c ? (d ? "variant" : "case") : (d ? "accent" : "base"), usage: "search" }).compare(a, b); } catch { return NaN; } }

///|
/// MapLibre's `Collator.resolvedLocale`; NUL where `Intl` throws.
extern "js" fn js_resolved_locale(has_locale : Bool, locale : String) -> String =
  #|(h, l) => { try { return new Intl.Collator(h ? l : []).resolvedOptions().locale; } catch { return "\0"; } }

///|
fn intl_number_format(
  x : Double,
  locale : String?,
  currency : String?,
  unit : String?,
  min : Double?,
  max : Double?,
) -> String? {
  let s = js_number_format(
    x,
    intl_flag(locale is Some(_), 1) |
    intl_flag(currency is Some(_), 2) |
    intl_flag(unit is Some(_), 4) |
    intl_flag(min is Some(_), 8) |
    intl_flag(max is Some(_), 16),
    locale.unwrap_or(""),
    currency.unwrap_or(""),
    unit.unwrap_or(""),
    min.unwrap_or(0.0),
    max.unwrap_or(0.0),
  )
  intl_text(s)
}

///|
fn intl_flag(given : Bool, bit : Int32) -> Int32 {
  if given {
    bit
  } else {
    0
  }
}

///|
fn intl_text(s : String) -> String? {
  if s == "\u{0}" {
    None
  } else {
    Some(s)
  }
}

///|
fn intl_collate(
  a : String,
  b : String,
  case : Bool,
  diacritic : Bool,
  locale : String?,
) -> Double {
  js_collate(a, b, case, diacritic, locale is Some(_), locale.unwrap_or(""))
}

///|
fn intl_resolved_locale(locale : String?) -> String? {
  intl_text(js_resolved_locale(locale is Some(_), locale.unwrap_or("")))
}
