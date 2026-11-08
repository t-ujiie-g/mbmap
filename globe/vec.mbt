///|
/// A point or direction in the globe's space: the unit sphere, y toward the
/// north pole, z toward (0°, 0°).
#derive(Debug, Eq)
pub(all) struct Vec3 {
  x : Double
  y : Double
  z : Double
}

///|
fn Vec3::dot(self : Vec3, o : Vec3) -> Double {
  self.x * o.x + self.y * o.y + self.z * o.z
}

///|
fn Vec3::length(self : Vec3) -> Double {
  self.dot(self).sqrt()
}

///|
fn Vec3::scale(self : Vec3, k : Double) -> Vec3 {
  { x: self.x * k, y: self.y * k, z: self.z * k, }
}

///|
fn Vec3::add(self : Vec3, o : Vec3) -> Vec3 {
  { x: self.x + o.x, y: self.y + o.y, z: self.z + o.z, }
}

///|
fn Vec3::sub(self : Vec3, o : Vec3) -> Vec3 {
  { x: self.x - o.x, y: self.y - o.y, z: self.z - o.z, }
}

///|
/// `self + o * k` (`scaleAndAdd`).
fn Vec3::add_scaled(self : Vec3, o : Vec3, k : Double) -> Vec3 {
  { x: self.x + o.x * k, y: self.y + o.y * k, z: self.z + o.z * k, }
}

///|
fn Vec3::cross(self : Vec3, o : Vec3) -> Vec3 {
  {
    x: self.y * o.z - self.z * o.y,
    y: self.z * o.x - self.x * o.z,
    z: self.x * o.y - self.y * o.x,
  }
}

///|
fn Vec3::normalize(self : Vec3) -> Vec3 {
  let len = self.dot(self)
  if len > 0.0 {
    self.scale(1.0 / len.sqrt())
  } else {
    self
  }
}

///|
fn Vec3::rotate_x(self : Vec3, rad : Double) -> Vec3 {
  let (s, c) = (@math.sin(rad), @math.cos(rad))
  { x: self.x, y: self.y * c - self.z * s, z: self.y * s + self.z * c, }
}

///|
fn Vec3::rotate_y(self : Vec3, rad : Double) -> Vec3 {
  let (s, c) = (@math.sin(rad), @math.cos(rad))
  { x: self.z * s + self.x * c, y: self.y, z: self.z * c - self.x * s, }
}

///|
fn Vec3::rotate_z(self : Vec3, rad : Double) -> Vec3 {
  let (s, c) = (@math.sin(rad), @math.cos(rad))
  { x: self.x * c - self.y * s, y: self.x * s + self.y * c, z: self.z, }
}

///|
/// `m * (v, 1)`.
fn transform(m : @core.Mat4, v : Vec3) -> (Double, Double, Double, Double) {
  m.apply(v.x, v.y, v.z, 1.0)
}

///|
priv struct Quat {
  x : Double
  y : Double
  z : Double
  w : Double
}

///|
/// gl-matrix's `fromEuler` (degrees, order zyx).
fn Quat::from_euler(x : Double, y : Double, z : Double) -> Quat {
  let half = @math.PI / 360.0
  let (x, y, z) = (x * half, y * half, z * half)
  let (sx, cx) = (@math.sin(x), @math.cos(x))
  let (sy, cy) = (@math.sin(y), @math.cos(y))
  let (sz, cz) = (@math.sin(z), @math.cos(z))
  {
    x: sx * cy * cz - cx * sy * sz,
    y: cx * sy * cz + sx * cy * sz,
    z: cx * cy * sz - sx * sy * cz,
    w: cx * cy * cz + sx * sy * sz,
  }
}

///|
fn Quat::mul(self : Quat, b : Quat) -> Quat {
  let { x: ax, y: ay, z: az, w: aw, } = self
  let { x: bx, y: by, z: bz, w: bw, } = b
  {
    x: ax * bw + aw * bx + ay * bz - az * by,
    y: ay * bw + aw * by + az * bx - ax * bz,
    z: az * bw + aw * bz + ax * by - ay * bx,
    w: aw * bw - ax * bx - ay * by - az * bz,
  }
}
