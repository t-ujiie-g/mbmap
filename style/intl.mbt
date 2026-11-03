///|
/// A host's `Intl` as `FeatureContext::number_format`, `collate` and
/// `resolved_locale` take it, for contexts that get it passed in.
pub(all) struct Intl {
  number_format : (Double, String?, String?, String?, Double?, Double?) -> String?
  collate : (String, String, Bool, Bool, String?) -> Double
  resolved_locale : (String?) -> String?
}

///|
/// What `FeatureContext` does by default: the JavaScript host's `Intl` on the
/// js backend, an approximation elsewhere.
pub fn Intl::fallback() -> Intl {
  {
    number_format: intl_number_format,
    collate: intl_collate,
    resolved_locale: intl_resolved_locale,
  }
}
