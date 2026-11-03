///|
/// Without the host's `Intl`: the number rounded to the most fraction digits
/// (3 unless given), its locale, currency and unit left out.
fn intl_number_format(
  x : Double,
  _locale : String?,
  _currency : String?,
  _unit : String?,
  min : Double?,
  max : Double?,
) -> String? {
  let digits = max.unwrap_or(@cmp.maximum(3.0, min.unwrap_or(0.0)))
  let k = @math.pow(10.0, digits)
  Some(((x * k).round() / k).to_string())
}

///|
/// Without the host's `Intl`: by UTF-16 code units, ASCII letters folded
/// unless case sensitive.
fn intl_collate(
  a : String,
  b : String,
  case : Bool,
  _diacritic : Bool,
  _locale : String?,
) -> Double {
  let fold = (s : String) => if case { s } else { s.to_lower() }
  str_compare(fold(a), fold(b)).to_double()
}

///|
fn intl_resolved_locale(locale : String?) -> String? {
  Some(locale.unwrap_or("en-US"))
}
