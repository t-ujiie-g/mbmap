///|
/// The transform `a` describes: viewport width and height, camera (lng, lat,
/// zoom, bearing, pitch), limits (min/max zoom, min/max pitch) and bounds
/// (west, south, east, north; NaN west for none).
fn transform_of(a : FixedArray[Double]) -> @core.Transform {
  let bounds : @core.LngLatBounds? = if a[11].is_nan() {
    None
  } else {
    Some({ west: a[11], south: a[12], east: a[13], north: a[14], })
  }
  @core.Transform::new(
    {
      center: { lng: a[2], lat: a[3], },
      zoom: a[4],
      bearing: a[5],
      pitch: a[6],
    },
    a[0],
    a[1],
    limits={
      min_zoom: a[7],
      max_zoom: a[8],
      min_pitch: a[9],
      max_pitch: a[10],
      bounds,
    },
  )
}

///|
fn camera_numbers(c : @core.Camera, out : Array[Double]) -> Unit {
  out.push(c.center.lng)
  out.push(c.center.lat)
  out.push(c.zoom)
  out.push(c.bearing)
  out.push(c.pitch)
}

///|
fn joined(values : Array[Double]) -> String {
  values.map(v => v.to_string()).join(",")
}

///|
/// The camera of `transform_of(a)` once kept to its limits.
#export_name("camera_constrain")
pub fn camera_constrain(a : FixedArray[Double]) -> String {
  let out = []
  camera_numbers(transform_of(a).camera, out)
  joined(out)
}

///|
/// Screen points of the lng, lat pairs in `pts`.
#export_name("camera_project")
pub fn camera_project(
  a : FixedArray[Double],
  pts : FixedArray[Double],
) -> String {
  let t = transform_of(a)
  let out = []
  for i in 0..<(pts.length() / 2) {
    let (x, y) = t.project({ lng: pts[i * 2], lat: pts[i * 2 + 1], })
    out.push(x)
    out.push(y)
  }
  joined(out)
}

///|
/// Ground points under the screen points in `pts`.
#export_name("camera_unproject")
pub fn camera_unproject(
  a : FixedArray[Double],
  pts : FixedArray[Double],
) -> String {
  let t = transform_of(a)
  let out = []
  for i in 0..<(pts.length() / 2) {
    let p = t.unproject(pts[i * 2], pts[i * 2 + 1])
    out.push(p.lng)
    out.push(p.lat)
  }
  joined(out)
}

///|
/// West, south, east, north of the view.
#export_name("camera_bounds")
pub fn camera_bounds(a : FixedArray[Double]) -> String {
  let b = transform_of(a).bounds()
  joined([b.west, b.south, b.east, b.north])
}

///|
/// `camera_for_bounds` of `b`: west, south, east, north, bearing, padding
/// (top, right, bottom, left), offset x and y, max zoom (NaN for the
/// limit); empty when it does not fit.
#export_name("camera_fit")
pub fn camera_fit(a : FixedArray[Double], b : FixedArray[Double]) -> String {
  let t = transform_of(a)
  let fit = t.camera_for_bounds(
    { west: b[0], south: b[1], east: b[2], north: b[3], },
    bearing=b[4],
    padding={ top: b[5], right: b[6], bottom: b[7], left: b[8], },
    offset=(b[9], b[10]),
    max_zoom?=if b[11].is_nan() { None } else { Some(b[11]) },
  )
  match fit {
    Some(c) => {
      let out = []
      camera_numbers(c, out)
      joined(out)
    }
    None => ""
  }
}

///|
/// The target `g` gives: center (lng, lat), zoom, bearing, pitch, around
/// (lng, lat), each NaN for none, then the offset x and y.
fn target_of(g : FixedArray[Double]) -> @core.CameraTarget {
  let some = (v : Double) => if v.is_nan() { None } else { Some(v) }
  @core.CameraTarget::new(
    center?=if g[0].is_nan() { None } else { Some({ lng: g[0], lat: g[1], }) },
    zoom?=some(g[2]),
    bearing?=some(g[3]),
    pitch?=some(g[4]),
    around?=if g[5].is_nan() { None } else { Some({ lng: g[5], lat: g[6], }) },
    offset=(g[7], g[8]),
  )
}

///|
/// Cameras of `ease_to(target_of(g))` at the eased fractions `ks`.
#export_name("camera_ease")
pub fn camera_ease(
  a : FixedArray[Double],
  g : FixedArray[Double],
  ks : FixedArray[Double],
) -> String {
  let e = transform_of(a).ease_to(target_of(g))
  let out = []
  for k in ks {
    camera_numbers(e.at(k), out)
  }
  joined(out)
}

///|
/// `fly_to(target_of(g))` with `o` (curve, speed, screen speed, min zoom;
/// NaN for the defaults): its duration, then the cameras at eased fractions
/// `ks`; empty when it is too short to fly.
#export_name("camera_fly")
pub fn camera_fly(
  a : FixedArray[Double],
  g : FixedArray[Double],
  o : FixedArray[Double],
  ks : FixedArray[Double],
) -> String {
  let some = (v : Double) => if v.is_nan() { None } else { Some(v) }
  guard transform_of(a).fly_to(
      target_of(g),
      curve=some(o[0]).unwrap_or(1.42),
      speed=some(o[1]).unwrap_or(1.2),
      screen_speed?=some(o[2]),
      min_zoom?=some(o[3]),
    )
    is Some(f) else {
    return ""
  }
  let out = [f.duration]
  for k in ks {
    camera_numbers(f.at(k), out)
  }
  joined(out)
}

///|
/// MapLibre's default easing at `ts`.
#export_name("camera_easing")
pub fn camera_easing(ts : FixedArray[Double]) -> String {
  let e = @core.Bezier::ease()
  joined(ts.iter().map(t => e.at(t)).collect())
}
