///|
/// The style's `sky` (with the Style Spec's defaults for what it leaves out;
/// without one, MapLibre draws neither sky nor fog): the sky's color
/// above the horizon blending into `horizon` over `sky_horizon_blend` of half
/// the screen, and terrain fading into `fog` (towards `horizon` farther out)
/// past `fog_ground_blend` of the depth. `atmosphere-blend` is for globes and
/// is not read.
pub struct Sky {
  sky : Expr
  horizon : Expr
  fog : Expr
  fog_ground_blend : Expr
  horizon_fog_blend : Expr
  sky_horizon_blend : Expr
}

///|
fn parse_sky(json : Json?) -> Sky? raise StyleError {
  let s = match json {
    None | Some(Null) => return None
    Some(Object(s)) => s
    Some(_) => raise Invalid(path="sky", "not an object")
  }
  let color = (key : String, default : String) => {
    paint_expr(s, key, "sky", ColorType, Json::string(default))
  }
  let number = (key : String, default : Double) => {
    paint_expr(s, key, "sky", NumberType, Json::number(default))
  }
  Some({
    sky: color("sky-color", "#88C6FC"),
    horizon: color("horizon-color", "#ffffff"),
    fog: color("fog-color", "#ffffff"),
    fog_ground_blend: number("fog-ground-blend", 0.5),
    horizon_fog_blend: number("horizon-fog-blend", 0.8),
    sky_horizon_blend: number("sky-horizon-blend", 0.8),
  })
}
