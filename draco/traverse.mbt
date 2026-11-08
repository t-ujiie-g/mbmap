// Ported from Draco 1.5.7 (compression/mesh/traverser/*, compression/attributes/linear_sequencer.h,
// mesh_attribute_indices_encoding_data.h): Apache License 2.0, Copyright 2016 The Draco Authors.
// See NOTICE.

///|
/// `MeshAttributeIndicesEncodingData`: `corners` is `encoded_attribute_value_index_to_corner_map`,
/// `vertex_values` `vertex_to_encoded_attribute_value_index_map`.
priv struct EncodingData {
  corners : Array[Int32]
  mut vertex_values : FixedArray[Int32]
  mut num_values : Int32
}

///|
fn EncodingData::new() -> EncodingData {
  { corners: [], vertex_values: [], num_values: 0, }
}

///|
/// A `PointsSequencer`: `Linear` numbers the points in order, the others traverse the mesh
/// (`MeshTraversalSequencer` with a depth-first or a max-prediction-degree traverser).
priv enum Sequencer {
  Linear(Int32)
  DepthFirst(Table, EncodingData)
  Degree(CornerTable, EncodingData)
}

///|
/// The visited flags and outputs a traversal shares with `MeshAttributeIndicesEncodingObserver`.
priv struct Visit {
  faces : FixedArray[Bool]
  vertices : FixedArray[Bool]
  enc : EncodingData
  mesh_faces : FixedArray[Int32]
  points : Array[Int32]
}

///|
fn Visit::new(
  t : Table,
  enc : EncodingData,
  mesh_faces : FixedArray[Int32],
  points : Array[Int32],
) -> Visit {
  {
    faces: FixedArray::make(t.face_count(), false),
    vertices: FixedArray::make(t.vertex_count(), false),
    enc,
    mesh_faces,
    points,
  }
}

///|
fn Visit::face_visited(self : Visit, c : Int32) -> Bool {
  c < 0 || self.faces[c / 3]
}

///|
fn Visit::vertex_visited(self : Visit, v : Int32) -> Bool {
  v < 0 || v >= self.vertices.length() || self.vertices[v]
}

///|
/// Marks `v` visited and records it as the observer does; false where Draco would index out of
/// bounds.
fn Visit::visit(self : Visit, v : Int32, c : Int32) -> Bool {
  guard v >= 0 &&
    v < self.vertices.length() &&
    v < self.enc.vertex_values.length() &&
    c >= 0 &&
    c < self.mesh_faces.length() else {
    return false
  }
  self.vertices[v] = true
  self.points.push(self.mesh_faces[c])
  self.enc.corners.push(c)
  self.enc.vertex_values[v] = self.enc.num_values
  self.enc.num_values += 1
  true
}

///|
fn depth_first(t : Table, visit : Visit) -> Bool {
  let stack : Array[Int32] = []
  for f in 0..<t.face_count() {
    let start = 3 * f
    if visit.face_visited(start) {
      continue
    }
    stack.clear()
    stack.push(start)
    let next_vert = t.vertex(next(start))
    let prev_vert = t.vertex(previous(start))
    guard next_vert >= 0 && prev_vert >= 0 else { return false }
    if !visit.vertex_visited(next_vert) {
      guard visit.visit(next_vert, next(start)) else { return false }
    }
    if !visit.vertex_visited(prev_vert) {
      guard visit.visit(prev_vert, previous(start)) else { return false }
    }
    while stack.length() > 0 {
      let mut corner = stack[stack.length() - 1]
      if corner < 0 || visit.faces[corner / 3] {
        let _ = stack.pop()
        continue
      }
      while true {
        guard corner >= 0 else { return false }
        visit.faces[corner / 3] = true
        let vert = t.vertex(corner)
        guard vert >= 0 else { return false }
        if !visit.vertex_visited(vert) {
          let boundary = t.on_boundary(vert)
          guard visit.visit(vert, corner) else { return false }
          if !boundary {
            corner = t.opposite(next(corner))
            continue
          }
        }
        let right = t.opposite(next(corner))
        let left = t.opposite(previous(corner))
        if visit.face_visited(right) {
          if visit.face_visited(left) {
            let _ = stack.pop()
            break
          }
          corner = left
        } else if visit.face_visited(left) {
          corner = right
        } else {
          stack[stack.length() - 1] = left
          stack.push(right)
          break
        }
      }
    }
  }
  true
}

///|
fn max_degree(t : CornerTable, visit : Visit) -> Bool {
  let degrees = FixedArray::make(t.vertex_count(), 0)
  if degrees.length() == 0 {
    return true
  }
  let stacks : FixedArray[Array[Int32]] = [[], [], []]
  let mut best = 0
  let priority = fn(c : Int32) -> Int32 {
    let tip = t.vertex(c)
    if visit.vertex_visited(tip) {
      0
    } else {
      degrees[tip] += 1
      if degrees[tip] > 1 {
        1
      } else {
        2
      }
    }
  }
  for f in 0..<t.face_count() {
    let start = 3 * f
    stacks[0].push(start)
    best = 0
    let next_vert = t.vertex(next(start))
    if !visit.vertex_visited(next_vert) {
      guard visit.visit(next_vert, next(start)) else { return false }
    }
    let prev_vert = t.vertex(previous(start))
    if !visit.vertex_visited(prev_vert) {
      guard visit.visit(prev_vert, previous(start)) else { return false }
    }
    let tip = t.vertex(start)
    if !visit.vertex_visited(tip) {
      guard visit.visit(tip, start) else { return false }
    }
    while true {
      let mut corner = -1
      for i in best..<3 {
        if stacks[i].length() > 0 {
          corner = stacks[i].unsafe_pop()
          best = i
          break
        }
      }
      if corner < 0 {
        break
      }
      if visit.faces[corner / 3] {
        continue
      }
      while true {
        visit.faces[corner / 3] = true
        let vert = t.vertex(corner)
        if !visit.vertex_visited(vert) {
          guard visit.visit(vert, corner) else { return false }
        }
        let right = t.opposite(next(corner))
        let left = t.opposite(previous(corner))
        let right_visited = visit.face_visited(right)
        let left_visited = visit.face_visited(left)
        if !left_visited {
          let p = priority(left)
          if right_visited && p <= best {
            corner = left
            continue
          }
          stacks[p].push(left)
          if p < best {
            best = p
          }
        }
        if !right_visited {
          let p = priority(right)
          if p <= best {
            corner = right
            continue
          }
          stacks[p].push(right)
          if p < best {
            best = p
          }
        }
        break
      }
    }
  }
  true
}

///|
/// `GenerateSequence`: the point ids in the order their values are stored.
fn Sequencer::generate(
  self : Sequencer,
  mesh_faces : FixedArray[Int32],
) -> Array[Int32]? {
  match self {
    Linear(n) => {
      guard n >= 0 else { return None }
      Some(Array::makei(n, fn(i) { i }))
    }
    DepthFirst(t, enc) => {
      let points = []
      guard depth_first(t, Visit::new(t, enc, mesh_faces, points)) else {
        return None
      }
      Some(points)
    }
    Degree(t, enc) => {
      let points = []
      guard max_degree(t, Visit::new(Main(t), enc, mesh_faces, points)) else {
        return None
      }
      Some(points)
    }
  }
}

///|
fn traversal_mapping(
  t : Table,
  enc : EncodingData,
  mesh_faces : FixedArray[Int32],
  num_points : Int32,
) -> FixedArray[Int32]? {
  let map = FixedArray::make(num_points, -1)
  for c in 0..<mesh_faces.length() {
    let point = mesh_faces[c]
    let vert = t.vertex(c)
    guard vert >= 0 && vert < enc.vertex_values.length() else { return None }
    let entry = enc.vertex_values[vert]
    guard ult(point, num_points) && ult(entry, num_points) else { return None }
    map[point] = entry
  }
  Some(map)
}

///|
/// `UpdatePointToAttributeIndexMapping`: None for the identity mapping, else each point's value.
fn Sequencer::mapping(
  self : Sequencer,
  mesh_faces : FixedArray[Int32],
  num_points : Int32,
) -> FixedArray[Int32]?? {
  match self {
    Linear(_) => Some(None)
    DepthFirst(t, enc) =>
      traversal_mapping(t, enc, mesh_faces, num_points).map(fn(m) { Some(m) })
    Degree(t, enc) =>
      traversal_mapping(Main(t), enc, mesh_faces, num_points).map(fn(m) {
        Some(m)
      })
  }
}
