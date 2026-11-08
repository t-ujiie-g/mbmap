///|
/// The globe camera `a` describes: `transform_of`'s numbers, then the
/// projection (0 mercator, 1 globe, 2 vertical perspective).
fn globe_of(a : FixedArray[Double]) -> @globe.Globe {
  let t = transform_of(a)
  @globe.Globe::new(
    {
      center: { lng: a[2], lat: a[3], },
      zoom: a[4],
      bearing: a[5],
      pitch: a[6],
    },
    a[0],
    a[1],
    limits=t.limits,
    projection=match a[15] {
      0.0 => Mercator
      2.0 => VerticalPerspective
      _ => Globe
    },
  )
}

///|
fn globe_numbers(g : @globe.Globe, out : Array[Double]) -> Unit {
  camera_numbers(g.camera(), out)
  out.push(g.transition())
}

///|
/// The camera of `globe_of(a)` once constrained, and its transition.
#export_name("globe_state")
pub fn globe_state(a : FixedArray[Double]) -> String {
  let out = []
  globe_numbers(globe_of(a), out)
  joined(out)
}

///|
/// Screen points of the lng, lat pairs in `pts`, each followed by 1 when it is
/// behind the globe.
#export_name("globe_project")
pub fn globe_project(
  a : FixedArray[Double],
  pts : FixedArray[Double],
) -> String {
  let g = globe_of(a)
  let out = []
  for i in 0..<(pts.length() / 2) {
    let p : @core.LngLat = { lng: pts[i * 2], lat: pts[i * 2 + 1], }
    let (x, y) = g.project(p)
    out.push(x)
    out.push(y)
    out.push(if g.occluded(p) { 1.0 } else { 0.0 })
  }
  joined(out)
}

///|
/// Places under the screen points in `pts`.
#export_name("globe_unproject")
pub fn globe_unproject(
  a : FixedArray[Double],
  pts : FixedArray[Double],
) -> String {
  let g = globe_of(a)
  let out = []
  for i in 0..<(pts.length() / 2) {
    let p = g.unproject(pts[i * 2], pts[i * 2 + 1])
    out.push(p.lng)
    out.push(p.lat)
  }
  joined(out)
}

///|
/// West, south, east, north of the view.
#export_name("globe_bounds")
pub fn globe_bounds(a : FixedArray[Double]) -> String {
  let b = globe_of(a).bounds()
  joined([b.west, b.south, b.east, b.north])
}

///|
/// The globe matrix (16), the projection (16), near and far, the camera
/// position (3), the clipping plane (4) and the camera's altitude in meters.
#export_name("globe_matrices")
pub fn globe_matrices(a : FixedArray[Double]) -> String {
  let g = globe_of(a)
  let (p, near, far) = g.projection()
  let c = g.camera_position()
  let (pa, pb, pc, pd) = g.clipping_plane_of()
  joined(
    [
      ..g.globe_matrix().m,
      ..p.m,
      near,
      far,
      c.x,
      c.y,
      c.z,
      pa,
      pb,
      pc,
      pd,
      g.camera_altitude(),
    ],
  )
}

///|
/// `camera_for_bounds` of `b` as in `camera_fit`.
#export_name("globe_fit")
pub fn globe_fit(a : FixedArray[Double], b : FixedArray[Double]) -> String {
  let fit = globe_of(a).camera_for_bounds(
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
/// Cameras and transitions of `ease_to(target_of(g))` at the eased fractions `ks`.
#export_name("globe_ease")
pub fn globe_ease(
  a : FixedArray[Double],
  g : FixedArray[Double],
  ks : FixedArray[Double],
) -> String {
  let e = globe_of(a).ease_to(target_of(g))
  let out = []
  for k in ks {
    let _ = e.at(k)
    globe_numbers(e.transform(), out)
  }
  joined(out)
}

///|
/// `fly_to` as `camera_fly`: its duration, then cameras and transitions at `ks`.
#export_name("globe_fly")
pub fn globe_fly(
  a : FixedArray[Double],
  g : FixedArray[Double],
  o : FixedArray[Double],
  ks : FixedArray[Double],
) -> String {
  let some = (v : Double) => if v.is_nan() { None } else { Some(v) }
  guard globe_of(a).fly_to(
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
    let _ = f.at(k)
    globe_numbers(f.transform(), out)
  }
  joined(out)
}

///|
/// Gesture frames, 7 numbers each (x, y, pan x, pan y, zoom, bearing and
/// pitch deltas), applied in turn; the camera and transition after each.
#export_name("globe_controls")
pub fn globe_controls(
  a : FixedArray[Double],
  ops : FixedArray[Double],
) -> String {
  let g = globe_of(a)
  let out = []
  for i in 0..<(ops.length() / 7) {
    let o = i * 7
    g.apply_controls(
      ops[o],
      ops[o + 1],
      pan=(ops[o + 2], ops[o + 3]),
      zoom=ops[o + 4],
      bearing=ops[o + 5],
      pitch=ops[o + 6],
    )
    g.update_transition()
    globe_numbers(g, out)
  }
  joined(out)
}

///|
/// The camera after `set_location_at_point` of each (lng, lat, x, y) in `p`, in turn.
#export_name("globe_at_point")
pub fn globe_at_point(a : FixedArray[Double], p : FixedArray[Double]) -> String {
  let g = globe_of(a)
  let out = []
  for i in 0..<(p.length() / 4) {
    g.set_location_at_point(
      { lng: p[i * 4], lat: p[i * 4 + 1], },
      p[i * 4 + 2],
      p[i * 4 + 3],
    )
    globe_numbers(g, out)
  }
  joined(out)
}

///|
/// `pan_inertia` of a pan (x, y): the center and offset it eases with.
#export_name("globe_inertia")
pub fn globe_inertia(
  a : FixedArray[Double],
  pan : FixedArray[Double],
) -> String {
  let (c, (ox, oy)) = globe_of(a).pan_inertia((pan[0], pan[1]))
  joined([c.lng, c.lat, ox, oy])
}
