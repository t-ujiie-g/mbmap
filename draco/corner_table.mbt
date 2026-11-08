// Ported from Draco 1.5.7 (mesh/corner_table.h, mesh/mesh_attribute_corner_table.cc,
// mesh/corner_table_iterators.h): Apache License 2.0, Copyright 2016 The Draco Authors. See NOTICE.

///|
fn next(c : Int32) -> Int32 {
  if c < 0 {
    -1
  } else if c % 3 == 2 {
    c - 2
  } else {
    c + 1
  }
}

///|
fn previous(c : Int32) -> Int32 {
  if c < 0 {
    -1
  } else if c % 3 == 0 {
    c + 2
  } else {
    c - 1
  }
}

///|
/// Draco's `CornerTable` as the edgebreaker decoder fills it.
priv struct CornerTable {
  c2v : FixedArray[Int32]
  opp : FixedArray[Int32]
  vcorners : Array[Int32]
}

///|
fn CornerTable::new(num_faces : Int32) -> CornerTable {
  {
    c2v: FixedArray::make(num_faces * 3, -1),
    opp: FixedArray::make(num_faces * 3, -1),
    vcorners: [],
  }
}

///|
fn CornerTable::opposite(self : CornerTable, c : Int32) -> Int32 {
  if c < 0 {
    -1
  } else {
    self.opp[c]
  }
}

///|
fn CornerTable::vertex(self : CornerTable, c : Int32) -> Int32 {
  if c < 0 {
    -1
  } else {
    self.c2v[c]
  }
}

///|
fn CornerTable::left_most(self : CornerTable, v : Int32) -> Int32 {
  if v < 0 || v >= self.vcorners.length() {
    -1
  } else {
    self.vcorners[v]
  }
}

///|
fn CornerTable::vertex_count(self : CornerTable) -> Int32 {
  self.vcorners.length()
}

///|
fn CornerTable::face_count(self : CornerTable) -> Int32 {
  self.c2v.length() / 3
}

///|
fn CornerTable::add_vertex(self : CornerTable) -> Int32 {
  self.vcorners.push(-1)
  self.vcorners.length() - 1
}

///|
fn CornerTable::set_left_most(self : CornerTable, v : Int32, c : Int32) -> Unit {
  if v >= 0 {
    self.vcorners[v] = c
  }
}

///|
/// `MeshAttributeCornerTable`: the corner table cut along an attribute's seams.
priv struct AttrTable {
  ct : CornerTable
  edge_seam : FixedArray[Bool]
  vertex_seam : FixedArray[Bool]
  c2v : FixedArray[Int32]
  left : Array[Int32]
  entries : Array[Int32]
}

///|
fn AttrTable::new(ct : CornerTable) -> AttrTable {
  let n = ct.c2v.length()
  {
    ct,
    edge_seam: FixedArray::make(n, false),
    vertex_seam: FixedArray::make(ct.vcorners.length(), false),
    c2v: FixedArray::make(n, -1),
    left: [],
    entries: [],
  }
}

///|
fn AttrTable::opposite(self : AttrTable, c : Int32) -> Int32 {
  if c < 0 || self.edge_seam[c] {
    -1
  } else {
    self.ct.opp[c]
  }
}

///|
fn AttrTable::vertex(self : AttrTable, c : Int32) -> Int32 {
  if c < 0 {
    -1
  } else {
    self.c2v[c]
  }
}

///|
fn AttrTable::left_most(self : AttrTable, v : Int32) -> Int32 {
  if v < 0 || v >= self.left.length() {
    -1
  } else {
    self.left[v]
  }
}

///|
fn AttrTable::vertex_count(self : AttrTable) -> Int32 {
  self.entries.length()
}

///|
fn AttrTable::face_count(self : AttrTable) -> Int32 {
  self.ct.c2v.length() / 3
}

///|
fn AttrTable::add_seam_edge(self : AttrTable, c : Int32) -> Unit {
  self.edge_seam[c] = true
  self.vertex_seam[self.ct.vertex(next(c))] = true
  self.vertex_seam[self.ct.vertex(previous(c))] = true
  let o = self.ct.opp[c]
  if o >= 0 {
    self.edge_seam[o] = true
    self.vertex_seam[self.ct.vertex(next(o))] = true
    self.vertex_seam[self.ct.vertex(previous(o))] = true
  }
}

///|
fn AttrTable::on_seam(self : AttrTable, c : Int32) -> Bool {
  self.vertex_seam[self.ct.vertex(c)]
}

///|
/// `RecomputeVertices(nullptr, nullptr)`. Fans are walked at most once around (Draco loops
/// forever on tables whose swings cycle elsewhere).
fn AttrTable::recompute_vertices(self : AttrTable) -> Bool {
  let ct = self.ct
  let limit = ct.c2v.length() + 1
  let mut count = 0
  for v in 0..<ct.vcorners.length() {
    let c = ct.vcorners[v]
    if c < 0 {
      continue
    }
    let mut first_vert = count
    count += 1
    self.entries.push(first_vert)
    let mut first_c = c
    if self.vertex_seam[v] {
      let mut act = self.swing_left(first_c)
      let mut steps = 0
      while act >= 0 {
        first_c = act
        act = self.swing_left(act)
        if act == c {
          return false
        }
        steps += 1
        guard steps <= limit else { return false }
      }
    }
    self.c2v[first_c] = first_vert
    self.left.push(first_c)
    let mut act = ct.swing_right(first_c)
    let mut steps = 0
    while act >= 0 && act != first_c {
      if self.edge_seam[next(act)] {
        first_vert = count
        count += 1
        self.entries.push(first_vert)
        self.left.push(act)
      }
      self.c2v[act] = first_vert
      act = ct.swing_right(act)
      steps += 1
      guard steps <= limit else { return false }
    }
  }
  true
}

///|
fn CornerTable::swing_left(self : CornerTable, c : Int32) -> Int32 {
  next(self.opposite(next(c)))
}

///|
fn CornerTable::swing_right(self : CornerTable, c : Int32) -> Int32 {
  previous(self.opposite(previous(c)))
}

///|
fn AttrTable::swing_left(self : AttrTable, c : Int32) -> Int32 {
  next(self.opposite(next(c)))
}

///|
/// The corner table a traversal or prediction walks: the mesh's, or one attribute's.
priv enum Table {
  Main(CornerTable)
  Seams(AttrTable)
}

///|
fn Table::opposite(self : Table, c : Int32) -> Int32 {
  match self {
    Main(t) => t.opposite(c)
    Seams(t) => t.opposite(c)
  }
}

///|
fn Table::vertex(self : Table, c : Int32) -> Int32 {
  match self {
    Main(t) => t.vertex(c)
    Seams(t) => t.vertex(c)
  }
}

///|
fn Table::left_most(self : Table, v : Int32) -> Int32 {
  match self {
    Main(t) => t.left_most(v)
    Seams(t) => t.left_most(v)
  }
}

///|
fn Table::vertex_count(self : Table) -> Int32 {
  match self {
    Main(t) => t.vertex_count()
    Seams(t) => t.vertex_count()
  }
}

///|
fn Table::face_count(self : Table) -> Int32 {
  match self {
    Main(t) => t.face_count()
    Seams(t) => t.face_count()
  }
}

///|
fn Table::swing_left(self : Table, c : Int32) -> Int32 {
  next(self.opposite(next(c)))
}

///|
fn Table::swing_right(self : Table, c : Int32) -> Int32 {
  previous(self.opposite(previous(c)))
}

///|
fn Table::on_boundary(self : Table, v : Int32) -> Bool {
  self.swing_left(self.left_most(v)) < 0
}
