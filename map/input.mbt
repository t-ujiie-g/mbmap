// The input handlers follow MapLibre GL JS 6.16.0's (src/ui/handler/,
// src/ui/handler_inertia.ts), BSD-3-Clause, Copyright (c) 2020, MapLibre
// contributors. See NOTICE.

///|
/// One step of a gesture, for inertia: when, and how it moved the map (pan
/// in screen pixels, zoom, bearing and pitch) around which screen point.
priv struct Sample {
  time : Double
  dx : Double
  dy : Double
  zoom : Double
  bearing : Double
  pitch : Double
  around : (Double, Double)
}

///|
/// Pixels a pointer may move before a press becomes a drag (MapLibre's
/// `clickTolerance`).
const CLICK_TOLERANCE : Double = 3.0

///|
/// Samples older than this many ms are dropped; velocity is measured over
/// the last `VELOCITY_WINDOW` ms (MapLibre's inertia buffer).
const BUFFER_CUTOFF : Double = 160.0

///|
const VELOCITY_WINDOW : Double = 60.0

///|
/// Easing of inertia (MapLibre's `bezier(0, 0, 0.3, 1)`).
let inertia_easing : @core.Bezier = @core.Bezier::new(0.0, 0.0, 0.3, 1.0)

///|
extern "js" fn event_bool(e : JsValue, key : String) -> Bool =
  #|(e, k) => !!e[k]

///|
extern "js" fn set_tab_index(c : @render_webgl2.Canvas) -> Unit =
  #|(c) => { if (!c.hasAttribute("tabindex")) c.setAttribute("tabindex", "0"); }

///|
/// A dashed box drawn over the canvas while a box zoom is dragged.
#external
priv type ZoomBox

///|
extern "js" fn zoom_box(c : @render_webgl2.Canvas) -> ZoomBox =
  #|(c) => {
  #|  const el = document.createElement("div");
  #|  el.style.cssText = "position:absolute;pointer-events:none;box-sizing:border-box;border:2px dotted #202020;background:rgba(255,255,255,0.3)";
  #|  c.parentElement?.append(el);
  #|  const resize = (x0, y0, x1, y1) => {
  #|    el.style.left = c.offsetLeft + Math.min(x0, x1) + "px";
  #|    el.style.top = c.offsetTop + Math.min(y0, y1) + "px";
  #|    el.style.width = Math.abs(x1 - x0) + "px";
  #|    el.style.height = Math.abs(y1 - y0) + "px";
  #|  };
  #|  return { resize, remove: () => el.remove() };
  #|}

///|
/// Moves the box to span (x0, y0) to (x1, y1), CSS px.
extern "js" fn ZoomBox::resize(
  self : ZoomBox,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Unit =
  #|(b, x0, y0, x1, y1) => b.resize(x0, y0, x1, y1)

///|
extern "js" fn ZoomBox::remove(self : ZoomBox) -> Unit =
  #|(b) => b.remove()

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
/// Whether two pointers moved together vertically: a two-finger pitch
/// (MapLibre's `TwoFingersTouchPitchHandler`).
fn vertical_together(
  before : Array[(Double, Double)],
  after : Array[(Double, Double)],
) -> Bool {
  let dy0 = after[0].1 - before[0].1
  let dy1 = after[1].1 - before[1].1
  let dx0 = after[0].0 - before[0].0
  let dx1 = after[1].0 - before[1].0
  dy0 * dy1 > 0.0 && dy0.abs() > dx0.abs() && dy1.abs() > dx1.abs()
}

///|
fn Map::record(self : Map, s : Sample) -> Unit {
  while self.inertia.length() > 0 &&
        s.time - self.inertia[0].time > BUFFER_CUTOFF {
    self.inertia.remove(0) |> ignore
  }
  self.inertia.push(s)
}

///|
/// A rotating drag turns (horizontal) and tilts (vertical); otherwise pointers
/// pan with their centroid and, two or more, zoom and turn around it (or tilt,
/// moving up or down together).
fn Map::on_pointer_move(self : Map, e : JsValue) -> Unit {
  let id = get_int(e, "pointerId")
  guard self.pointer_index(id) is Some(i) else { return }
  let x = get_double(e, "offsetX")
  let y = get_double(e, "offsetY")
  if self.box_start is Some((x0, y0, box)) {
    box.resize(x0, y0, x, y)
    return
  }
  if !self.dragging {
    let (sx, sy) = self.press
    if ((x - sx) * (x - sx) + (y - sy) * (y - sy)).sqrt() < CLICK_TOLERANCE &&
      self.pointers.length() == 1 {
      return
    }
    self.dragging = true
  }
  let before = self.pointer_list()
  self.pointers[i] = (id, x, y)
  let after = self.pointer_list()
  let t = self.transform
  let c = t.camera
  let event = as_event(e)
  if self.rotating && after.length() == 1 {
    guard self.handler_enabled(DragRotate) else { return }
    let bearing = -(after[0].0 - before[0].0) * ROTATE_RATE
    let pitch = -(after[0].1 - before[0].1) * PITCH_RATE
    self.move_camera(
      match self.globe {
        Some(g) =>
          self.globe_gesture(g, t.width / 2.0, t.height / 2.0, bearing~, pitch~)
        None => { ..c, bearing: c.bearing + bearing, pitch: c.pitch + pitch, }
      },
      event,
    )
    self.record({
      time: now(),
      dx: 0.0,
      dy: 0.0,
      zoom: 0.0,
      bearing,
      pitch,
      around: (t.width / 2.0, t.height / 2.0),
    })
    return
  }
  let (x0, y0, s0) = centroid(before)
  let (x1, y1, s1) = centroid(after)
  if after.length() == 2 &&
    self.handler_enabled(TouchPitch) &&
    vertical_together(before, after) {
    let pitch = -(y1 - y0) * PITCH_RATE
    self.move_camera(
      match self.globe {
        Some(g) => self.globe_gesture(g, x1, y1, pitch~)
        None => { ..c, pitch: c.pitch + pitch, }
      },
      event,
    )
    self.record({
      time: now(),
      dx: 0.0,
      dy: 0.0,
      zoom: 0.0,
      bearing: 0.0,
      pitch,
      around: (x1, y1),
    })
    return
  }
  let pan = self.handler_enabled(DragPan)
  if self.globe is Some(g) {
    let touch = after.length() >= 2 &&
      s0 > 0.0 &&
      s1 > 0.0 &&
      self.handler_enabled(TouchZoomRotate)
    let d = if pan { (x1 - x0, y1 - y0) } else { (0.0, 0.0) }
    let zoom = if touch { @math.log2(s1 / s0) } else { 0.0 }
    let bearing = if touch { -(angle(after) - angle(before)) } else { 0.0 }
    if !pan && !touch {
      return
    }
    self.move_camera(
      self.globe_gesture(g, x1, y1, pan=d, zoom~, bearing~),
      event,
    )
    self.record({
      time: now(),
      dx: d.0,
      dy: d.1,
      zoom,
      bearing,
      pitch: 0.0,
      around: (x1, y1),
    })
    return
  }
  let panned = if pan { t.with_camera(t.panned(x0, y0, x1, y1)) } else { t }
  if after.length() < 2 ||
    s0 <= 0.0 ||
    s1 <= 0.0 ||
    !self.handler_enabled(TouchZoomRotate) {
    if pan {
      self.move_camera(panned.camera, event)
      self.record({
        time: now(),
        dx: x1 - x0,
        dy: y1 - y0,
        zoom: 0.0,
        bearing: 0.0,
        pitch: 0.0,
        around: (x1, y1),
      })
    }
    return
  }
  let p = panned.camera
  let zoom = @math.log2(s1 / s0)
  let bearing = -(angle(after) - angle(before))
  self.move_camera(
    panned.keeping(x1, y1, {
      ..p,
      zoom: p.zoom + zoom,
      bearing: p.bearing + bearing,
    }),
    event,
  )
  self.record({
    time: now(),
    dx: if pan {
      x1 - x0
    } else {
      0.0
    },
    dy: if pan {
      y1 - y0
    } else {
      0.0
    },
    zoom,
    bearing,
    pitch: 0.0,
    around: (x1, y1),
  })
}

///|
/// The ease that carries a gesture's last velocity on (MapLibre's
/// `HandlerInertia._onMoveEnd`), or None if it was not moving.
fn Map::inertia_move(self : Map) -> (@core.CameraTarget, Double)? {
  let samples = self.inertia
  let at = now()
  while samples.length() > 0 && at - samples[0].time > BUFFER_CUTOFF {
    samples.remove(0) |> ignore
  }
  let mut first = @cmp.maximum(0, samples.length() - 2)
  while first > 0 && samples[first - 1].time >= at - VELOCITY_WINDOW {
    first -= 1
  }
  if samples.length() - first < 2 {
    samples.clear()
    return None
  }
  let mut dx = 0.0
  let mut dy = 0.0
  let mut zoom = 0.0
  let mut bearing = 0.0
  let mut pitch = 0.0
  for i in (first + 1)..<samples.length() {
    let s = samples[i]
    dx += s.dx
    dy += s.dy
    zoom += s.zoom
    bearing += s.bearing
    pitch += s.pitch
  }
  let around = samples[samples.length() - 1].around
  let duration = at - samples[first].time
  samples.clear()
  let pan = (dx * dx + dy * dy).sqrt()
  if pan == 0.0 && zoom == 0.0 && bearing == 0.0 && pitch == 0.0 {
    return None
  }
  // `calculateEasing`: how far and how long the motion coasts.
  let coast = (amount : Double, deceleration : Double, max_speed : Double) => {
    let speed = @cmp.maximum(
      -max_speed,
      @cmp.minimum(max_speed, amount * 0.3 / (duration / 1000.0)),
    )
    let d = speed.abs() / (deceleration * 0.3)
    (speed * (d / 2.0), d * 1000.0)
  }
  let t = self.transform
  let c = t.camera
  let mut ms = 0.0
  let mut offset = (0.0, 0.0)
  let mut center = None
  if pan > 0.0 {
    let (amount, d) = coast(pan, 2500.0, 1400.0)
    match self.globe {
      // The globe turns under the pan instead (`handlePanInertia`).
      Some(g) => {
        let (to, by) = g.pan_inertia((dx * amount / pan, dy * amount / pan))
        offset = by
        center = Some(to)
      }
      None => {
        // Never past the horizon: beyond it the pan would run backwards.
        let k = amount /
          pan *
          @cmp.minimum(t.horizon().abs() * 0.75 / amount.abs(), 1.0)
        offset = (dx * k, dy * k)
        center = Some(c.center)
      }
    }
    ms = @cmp.maximum(ms, d)
  }
  let mut target_zoom = None
  if zoom != 0.0 {
    let (amount, d) = coast(zoom, 20.0, 1400.0)
    target_zoom = Some(c.zoom + amount)
    ms = @cmp.maximum(ms, d)
  }
  let mut target_bearing = None
  if bearing != 0.0 {
    let (amount, d) = coast(bearing, 1000.0, 360.0)
    target_bearing = Some(
      c.bearing + @cmp.maximum(-179.0, @cmp.minimum(179.0, amount)),
    )
    ms = @cmp.maximum(ms, d)
  }
  let mut target_pitch = None
  if pitch != 0.0 {
    let (amount, d) = coast(pitch, 1000.0, 90.0)
    target_pitch = Some(c.pitch + amount)
    ms = @cmp.maximum(ms, d)
  }
  let around = if target_zoom is Some(_) || target_bearing is Some(_) {
    Some(self.point_location(around.0, around.1))
  } else {
    None
  }
  Some(
    (
      @core.CameraTarget::new(
        center?,
        zoom?=target_zoom,
        bearing?=target_bearing,
        pitch?=target_pitch,
        around?,
        offset~,
      ),
      ms,
    ),
  )
}

///|
fn Map::on_pointer_up(self : Map, e : JsValue) -> Unit {
  if self.pointer_index(get_int(e, "pointerId")) is Some(i) {
    self.pointers.remove(i) |> ignore
  }
  if !self.pointers.is_empty() {
    return
  }
  if self.box_start is Some((x0, y0, box)) {
    box.remove()
    self.box_start = None
    let x1 = get_double(e, "offsetX")
    let y1 = get_double(e, "offsetY")
    let t = self.transform
    let a = t.unproject(x0, y0)
    let b = t.unproject(x1, y1)
    let box : @core.LngLatBounds = {
      west: @cmp.minimum(a.lng, b.lng),
      south: @cmp.minimum(a.lat, b.lat),
      east: @cmp.maximum(a.lng, b.lng),
      north: @cmp.maximum(a.lat, b.lat),
    }
    if (x1 - x0).abs() > 0.0 &&
      (y1 - y0).abs() > 0.0 &&
      t.camera_for_bounds(box, bearing=t.camera.bearing) is Some(c) {
      self.ease_to(
        @core.CameraTarget::new(center=c.center, zoom=c.zoom, bearing=c.bearing),
        event=as_event(e),
      )
    }
    return
  }
  let was_dragging = self.dragging
  self.dragging = false
  if was_dragging && self.inertia_move() is Some((target, ms)) {
    self.ease_to(
      target,
      duration=ms,
      easing=t => inertia_easing.at(t),
      event=as_event(e),
    )
  } else {
    self.end_move(as_event(e))
  }
}

///|
fn Map::on_key_down(self : Map, e : JsValue) -> Unit {
  if !self.handler_enabled(Keyboard) ||
    event_bool(e, "altKey") ||
    event_bool(e, "ctrlKey") ||
    event_bool(e, "metaKey") {
    return
  }
  let shift = event_bool(e, "shiftKey")
  let (zoom, bearing, pitch, x, y) = match get_int(e, "keyCode") {
    61 | 107 | 171 | 187 => (1.0, 0.0, 0.0, 0.0, 0.0)
    189 | 109 | 173 => (-1.0, 0.0, 0.0, 0.0, 0.0)
    37 =>
      if shift {
        (0.0, -1.0, 0.0, 0.0, 0.0)
      } else {
        (0.0, 0.0, 0.0, -1.0, 0.0)
      }
    39 =>
      if shift {
        (0.0, 1.0, 0.0, 0.0, 0.0)
      } else {
        (0.0, 0.0, 0.0, 1.0, 0.0)
      }
    38 =>
      if shift {
        (0.0, 0.0, 1.0, 0.0, 0.0)
      } else {
        (0.0, 0.0, 0.0, 0.0, -1.0)
      }
    40 =>
      if shift {
        (0.0, 0.0, -1.0, 0.0, 0.0)
      } else {
        (0.0, 0.0, 0.0, 0.0, 1.0)
      }
    _ => return
  }
  if x != 0.0 || y != 0.0 {
    prevent_default(e)
  }
  let c = self.transform.camera
  let rotate = self.handler_enabled(DragRotate)
  self.ease_to(
    @core.CameraTarget::new(
      center=c.center,
      zoom=c.zoom + zoom * (if shift { 2.0 } else { 1.0 }),
      bearing=c.bearing + (if rotate { bearing * 15.0 } else { 0.0 }),
      pitch=c.pitch + (if rotate { pitch * 10.0 } else { 0.0 }),
      offset=(-x * 100.0, -y * 100.0),
    ),
    duration=300.0,
    easing=t => t * (2.0 - t),
    id="keyboard",
    event=as_event(e),
  )
}

///|
fn Map::attach_input(self : Map) -> Unit {
  let c = self.canvas
  set_tab_index(c)
  self.cleanups.push(prevent_context_menu(c))
  self.cleanups.push(
    listen(c, "pointerdown", e => {
      capture_pointer(c, e)
      self.stop()
      let x = get_double(e, "offsetX")
      let y = get_double(e, "offsetY")
      if self.pointers.is_empty() {
        self.rotating = rotating_drag(e)
        self.dragging = false
        self.press = (x, y)
        self.inertia.clear()
        if event_bool(e, "shiftKey") &&
          get_int(e, "button") == 0 &&
          self.handler_enabled(BoxZoom) {
          self.box_start = Some((x, y, zoom_box(c)))
        }
      }
      let id = get_int(e, "pointerId")
      if self.pointer_index(id) is Some(i) {
        self.pointers.remove(i) |> ignore
      }
      self.pointers.push((id, x, y))
    }),
  )
  self.cleanups.push(listen(c, "pointermove", e => self.on_pointer_move(e)))
  for type_ in ["pointerup", "pointercancel"] {
    self.cleanups.push(listen(c, type_, e => self.on_pointer_up(e)))
  }
  self.cleanups.push(
    listen(c, "wheel", e => {
      guard self.handler_enabled(ScrollZoom) else { return }
      prevent_default(e)
      self.stop()
      let delta = -wheel_pixels(e) * WHEEL_ZOOM_RATE
      let x = get_double(e, "offsetX")
      let y = get_double(e, "offsetY")
      self.move_camera(
        match self.globe {
          Some(g) => self.globe_gesture(g, x, y, zoom=delta)
          None =>
            self.transform.zoomed_around(
              x,
              y,
              self.transform.camera.zoom + delta,
            )
        },
        as_event(e),
      )
      if self.wheel_timer >= 0 {
        clear_timeout(self.wheel_timer)
      }
      self.wheel_timer = set_timeout(
        () => {
          self.wheel_timer = -1
          self.end_move(as_event(e))
        },
        WHEEL_END_DELAY,
      )
    }),
  )
  self.cleanups.push(
    listen(c, "dblclick", e => {
      guard self.handler_enabled(DoubleClickZoom) else { return }
      prevent_default(e)
      let t = self.transform
      let x = get_double(e, "offsetX")
      let y = get_double(e, "offsetY")
      let around = match self.globe {
        Some(g) =>
          if g.on_surface(x, y) {
            Some(g.unproject(x, y))
          } else {
            None
          }
        None =>
          if y > t.height / 2.0 - t.horizon() {
            Some(t.unproject(x, y))
          } else {
            None
          }
      }
      self.ease_to(
        @core.CameraTarget::new(
          zoom=t.camera.zoom +
            (if event_bool(e, "shiftKey") { -1.0 } else { 1.0 }),
          around?,
        ),
        duration=300.0,
        event=as_event(e),
      )
    }),
  )
  self.cleanups.push(listen(c, "keydown", e => self.on_key_down(e)))
}
