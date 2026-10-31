///|
/// Active pointers' positions, in the order they went down (pairs keep their
/// order between events).
fn Map::pointer_list(self : Map) -> Array[(Double, Double)] {
  self.pointers.map(p => (p.1, p.2))
}

///|
fn Map::pointer_index(self : Map, id : Int32) -> Int32? {
  self.pointers.search_by(p => p.0 == id)
}

///|
/// Mean position and spread of `points`.
fn centroid(points : Array[(Double, Double)]) -> (Double, Double, Double) {
  let n = points.length().to_double()
  let mut x = 0.0
  let mut y = 0.0
  for p in points {
    x += p.0
    y += p.1
  }
  x /= n
  y /= n
  let mut spread = 0.0
  for p in points {
    spread += ((p.0 - x) * (p.0 - x) + (p.1 - y) * (p.1 - y)).sqrt()
  }
  (x, y, spread / n)
}

///|
/// Direction in degrees from the first to the second point (clockwise, as the
/// screen's y axis points down).
fn angle(points : Array[(Double, Double)]) -> Double {
  let (a, b) = (points[0], points[1])
  @math.atan2(b.1 - a.1, b.0 - a.0) * 180.0 / @math.PI
}

///|
/// A rotating drag turns (horizontal) and tilts (vertical); otherwise pointers
/// pan with their centroid and, two or more, zoom and turn around it.
fn Map::on_pointer_move(self : Map, e : JsValue) -> Unit {
  let id = get_int(e, "pointerId")
  guard self.pointer_index(id) is Some(i) else { return }
  let before = self.pointer_list()
  self.pointers[i] = (id, get_double(e, "offsetX"), get_double(e, "offsetY"))
  let after = self.pointer_list()
  let t = self.transform
  let c = t.camera
  if self.rotating && after.length() == 1 {
    self.apply_camera({
      ..c,
      bearing: c.bearing - (after[0].0 - before[0].0) * ROTATE_RATE,
      pitch: c.pitch - (after[0].1 - before[0].1) * PITCH_RATE,
    })
    return
  }
  let (x0, y0, s0) = centroid(before)
  let (x1, y1, s1) = centroid(after)
  let panned = t.with_camera(t.panned(x0, y0, x1, y1))
  if after.length() < 2 || s0 <= 0.0 || s1 <= 0.0 {
    self.apply_camera(panned.camera)
    return
  }
  let p = panned.camera
  self.apply_camera(
    panned.keeping(x1, y1, {
      ..p,
      zoom: p.zoom + @math.log2(s1 / s0),
      bearing: p.bearing - (angle(after) - angle(before)),
    }),
  )
}

///|
fn Map::attach_input(self : Map) -> Unit {
  let c = self.canvas
  self.cleanups.push(prevent_context_menu(c))
  self.cleanups.push(
    listen(c, "pointerdown", e => {
      capture_pointer(c, e)
      if self.pointers.is_empty() {
        self.rotating = rotating_drag(e)
      }
      let id = get_int(e, "pointerId")
      if self.pointer_index(id) is Some(i) {
        self.pointers.remove(i) |> ignore
      }
      self.pointers.push(
        (id, get_double(e, "offsetX"), get_double(e, "offsetY")),
      )
    }),
  )
  self.cleanups.push(listen(c, "pointermove", e => self.on_pointer_move(e)))
  for type_ in ["pointerup", "pointercancel"] {
    self.cleanups.push(
      listen(c, type_, e => {
        if self.pointer_index(get_int(e, "pointerId")) is Some(i) {
          self.pointers.remove(i) |> ignore
        }
      }),
    )
  }
  self.cleanups.push(
    listen(c, "wheel", e => {
      prevent_default(e)
      let zoom = self.transform.camera.zoom - wheel_pixels(e) * WHEEL_ZOOM_RATE
      self.apply_camera(
        self.transform.zoomed_around(
          get_double(e, "offsetX"),
          get_double(e, "offsetY"),
          zoom,
        ),
      )
    }),
  )
}
