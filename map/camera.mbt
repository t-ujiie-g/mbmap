///|
/// A camera move in progress: `at` gives the camera at an eased fraction, `easing`
/// maps elapsed time (of `duration` ms) to it; a move with the same `id` replaces
/// it without ending the movement (MapLibre's `easeId`).
priv struct Animation {
  at : (Double) -> @core.Camera
  start : Double
  duration : Double
  easing : (Double) -> Double
  id : String
  event : Event
}

///|
/// Which inputs move the map, as MapLibre names its handlers.
pub(all) enum Handler {
  DragPan
  ScrollZoom
  BoxZoom
  DragRotate
  Keyboard
  DoubleClickZoom
  TouchZoomRotate
  TouchPitch
}

///|
fn Handler::bit(self : Handler) -> Int32 {
  match self {
    DragPan => 1
    ScrollZoom => 2
    BoxZoom => 4
    DragRotate => 8
    Keyboard => 16
    DoubleClickZoom => 32
    TouchZoomRotate => 64
    TouchPitch => 128
  }
}

///|
const ALL_HANDLERS : Int32 = 255

///|
/// How long after the last wheel event a scroll zoom ends, in ms.
const WHEEL_END_DELAY : Double = 200.0

///|
extern "js" fn set_timeout(f : () -> Unit, ms : Double) -> Int32 =
  #|(f, ms) => setTimeout(f, ms)

///|
extern "js" fn clear_timeout(id : Int32) -> Unit =
  #|(id) => clearTimeout(id)

///|
/// MapLibre's default easing.
let default_easing : @core.Bezier = @core.Bezier::ease()

///|
fn ease(t : Double) -> Double {
  default_easing.at(t)
}

///|
/// The map's current view, for projecting points, reading bounds and fitting
/// boxes (`@core.Transform::project`, `unproject`, `bounds`,
/// `camera_for_bounds`).
pub fn Map::transform(self : Map) -> @core.Transform {
  self.transform
}

///|
/// Sets the zoom and pitch ranges and bounds the camera keeps to; the camera
/// moves at once if it is outside them.
pub fn Map::set_limits(self : Map, limits : @core.Limits) -> Unit {
  let next = self.transform.with_limits(limits)
  let moved = next.camera != self.transform.camera
  self.transform = next
  if moved {
    self.begin_move(no_event())
    self.fire_move(next.camera)
    self.end_move(no_event())
  }
  self.request_render()
}

///|
/// Turns an input handler on or off; turning one off stops what it is doing.
pub fn Map::set_handler(self : Map, h : Handler, enabled : Bool) -> Unit {
  self.handlers = if enabled {
    self.handlers | h.bit()
  } else {
    self.handlers & h.bit().lnot()
  }
}

///|
fn Map::handler_enabled(self : Map, h : Handler) -> Bool {
  (self.handlers & h.bit()) != 0
}

///|
/// Calls `f` when the camera starts moving (with the input event that moved
/// it, or null for a call); returns an id for `off`.
pub fn Map::on_move_start(self : Map, f : (Event) -> Unit) -> Int32 {
  self.next_listener += 1
  self.listeners.set(self.next_listener, Start(f))
  self.next_listener
}

///|
/// Calls `f` when the camera stops: after a gesture, its inertia or an
/// animation; returns an id for `off`.
pub fn Map::on_move_end(self : Map, f : (Event) -> Unit) -> Int32 {
  self.next_listener += 1
  self.listeners.set(self.next_listener, End(f))
  self.next_listener
}

///|
/// The input event behind the current camera change, or null.
pub fn Map::input_event(self : Map) -> Event {
  self.input_event
}

///|
/// Whether the camera is moving: a gesture, inertia or an animation.
pub fn Map::is_moving(self : Map) -> Bool {
  self.moving
}

///|
/// Whether an animation (`ease_to`, `fly_to`) is running.
pub fn Map::is_easing(self : Map) -> Bool {
  self.animation is Some(_)
}

///|
fn Map::begin_move(self : Map, event : Event) -> Unit {
  if self.moving {
    return
  }
  self.moving = true
  for _, l in self.listeners {
    if l is Start(f) {
      f(event)
    }
  }
}

///|
/// Ends the movement unless a gesture or an animation still runs.
fn Map::end_move(self : Map, event : Event) -> Unit {
  if !self.moving || self.animation is Some(_) || !self.pointers.is_empty() {
    return
  }
  self.moving = false
  for _, l in self.listeners {
    if l is End(f) {
      f(event)
    }
  }
}

///|
/// Moves the camera for an input event: starts the movement if needed and
/// fires `move` with the event at hand.
fn Map::move_camera(self : Map, camera : @core.Camera, event : Event) -> Unit {
  if self.transform.with_camera(camera).camera == self.transform.camera {
    return
  }
  self.begin_move(event)
  self.input_event = event
  self.apply_camera(camera)
  self.input_event = no_event()
}

///|
/// Stops a running animation; the movement ends unless `keep` (a move that
/// takes over at once).
pub fn Map::stop(self : Map) -> Unit {
  self.stop_animation(false, "")
}

///|
fn Map::stop_animation(self : Map, keep : Bool, id : String) -> Unit {
  guard self.animation is Some(a) else { return }
  self.animation = None
  if !(keep && a.id != "" && a.id == id) {
    self.end_move(a.event)
  }
}

///|
/// Runs `at` over `duration` ms; 0 jumps to its end.
fn Map::animate(
  self : Map,
  at : (Double) -> @core.Camera,
  duration : Double,
  easing : (Double) -> Double,
  id : String,
  event : Event,
) -> Unit {
  self.stop_animation(true, id)
  self.begin_move(event)
  if duration <= 0.0 || duration.is_nan() {
    self.input_event = event
    self.apply_camera(at(1.0))
    self.input_event = no_event()
    self.end_move(event)
    return
  }
  self.animation = Some({ at, start: now(), duration, easing, id, event, })
  self.request_render()
}

///|
/// Advances the animation to this frame; called at the start of each frame.
fn Map::step_animation(self : Map) -> Unit {
  guard self.animation is Some(a) else { return }
  let t = @cmp.minimum((now() - a.start) / a.duration, 1.0)
  self.input_event = a.event
  self.apply_camera((a.at)((a.easing)(t)))
  self.input_event = no_event()
  if t >= 1.0 {
    // `apply_camera`'s listeners may have started another animation.
    if self.animation is Some(b) && physical_equal(a.at, b.at) {
      self.animation = None
      self.end_move(a.event)
    }
  } else {
    self.request_render()
  }
}

///|
/// Moves to `target` over `duration` ms, easing zoom, bearing, pitch and
/// center together (MapLibre's `easeTo`).
pub fn Map::ease_to(
  self : Map,
  target : @core.CameraTarget,
  duration~ : Double = 500.0,
  easing~ : (Double) -> Double = ease,
  id~ : String = "",
  event~ : Event = no_event(),
) -> Unit {
  let e = self.transform.ease_to(target)
  self.animate(k => e.at(k), duration, easing, id, event)
}

///|
/// Flies to `target`, zooming out and back in on the way (MapLibre's
/// `flyTo`): over `duration` ms if given, else at `speed` (or `screen_speed`);
/// a flight longer than `max_duration` ms jumps.
pub fn Map::fly_to(
  self : Map,
  target : @core.CameraTarget,
  duration? : Double,
  curve~ : Double = 1.42,
  speed~ : Double = 1.2,
  screen_speed? : Double,
  max_duration? : Double,
  min_zoom? : Double,
  easing~ : (Double) -> Double = ease,
  event~ : Event = no_event(),
) -> Unit {
  guard self.transform.fly_to(target, curve~, speed~, screen_speed?, min_zoom?)
    is Some(f) else {
    self.ease_to(target, duration=duration.unwrap_or(500.0), easing~, event~)
    return
  }
  let d = duration.unwrap_or(f.duration)
  let d = match max_duration {
    Some(m) if d > m => 0.0
    _ => d
  }
  self.animate(k => f.at(k), d, easing, "", event)
}
