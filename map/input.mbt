///|
/// Mean position and spread of the active pointers.
fn Map::pointer_centroid(self : Map) -> (Double, Double, Double) {
  let mut x = 0.0
  let mut y = 0.0
  let n = self.pointers.length().to_double()
  for _, p in self.pointers {
    x += p.0
    y += p.1
  }
  x /= n
  y /= n
  let mut spread = 0.0
  for _, p in self.pointers {
    spread += ((p.0 - x) * (p.0 - x) + (p.1 - y) * (p.1 - y)).sqrt()
  }
  (x, y, spread / n)
}

///|
/// Pans by the pointers' centroid motion and, with two or more pointers,
/// zooms by how much they spread apart, around the centroid.
fn Map::on_pointer_move(self : Map, e : JsValue) -> Unit {
  let id = get_int(e, "pointerId")
  if !self.pointers.contains(id) || self.pointers.length() == 0 {
    return
  }
  let (x0, y0, s0) = self.pointer_centroid()
  self.pointers.set(id, (get_double(e, "offsetX"), get_double(e, "offsetY")))
  let (x1, y1, s1) = self.pointer_centroid()
  let panned = self.transform.with_camera(
    self.transform.panned(x1 - x0, y1 - y0),
  )
  let camera = if self.pointers.length() >= 2 && s0 > 0.0 && s1 > 0.0 {
    panned.zoomed_around(x1, y1, panned.camera.zoom + @math.log2(s1 / s0))
  } else {
    panned.camera
  }
  self.apply_camera(camera)
}

///|
fn Map::attach_input(self : Map) -> Unit {
  let c = self.canvas
  self.cleanups.push(
    listen(c, "pointerdown", e => {
      capture_pointer(c, e)
      self.pointers.set(
        get_int(e, "pointerId"),
        (get_double(e, "offsetX"), get_double(e, "offsetY")),
      )
    }),
  )
  self.cleanups.push(listen(c, "pointermove", e => self.on_pointer_move(e)))
  for type_ in ["pointerup", "pointercancel"] {
    self.cleanups.push(
      listen(c, type_, e => self.pointers.remove(get_int(e, "pointerId"))),
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
