///|
/// The style's `projection` type: MapLibre's `"mercator"`, `"globe"` (vertical
/// perspective up to zoom 11, mercator from 12) and `"vertical-perspective"`.
pub(all) enum ProjectionType {
  Mercator
  Globe
  VerticalPerspective
}

///|
fn parse_projection(json : Json?) -> ProjectionType raise StyleError {
  let p = match json {
    None | Some(Null) => return Mercator
    Some(Object(p)) => p
    Some(_) => raise Invalid(path="projection", "not an object")
  }
  match p.get("type") {
    None | Some(String("mercator")) => Mercator
    Some(String("globe")) => Globe
    Some(String("vertical-perspective")) => VerticalPerspective
    Some(Array(_)) => raise Unsupported(path="projection.type", "expressions")
    Some(_) => raise Invalid(path="projection.type", "not a projection")
  }
}

///|
/// The sky's `atmosphere-blend`, drawn on the globe also when the style has no
/// `sky` (MapLibre keeps one with the defaults).
fn parse_atmosphere(json : Json?) -> Expr raise StyleError {
  let sky = match json {
    Some(Object(s)) => s
    _ => {}
  }
  paint_expr(sky, "atmosphere-blend", "sky", NumberType, Json::number(0.8))
}
