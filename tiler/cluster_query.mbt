// Ported from @maplibre/geojson-vt 6.3.0 (src/cluster-tile-index.ts): MIT
// License, Copyright (c) 2025 MapLibre contributors, and ISC License,
// Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// The tree a zoom draws from (geojson-vt's `limitZoom`).
fn ClusterIndex::tree_at(self : ClusterIndex, z : Int32) -> ClusterTree? {
  let o = self.options
  let z = @cmp.maximum(o.min_zoom, @cmp.minimum(z, o.max_zoom + 1))
  if z >= 0 && z < self.trees.length() {
    self.trees[z]
  } else {
    None
  }
}

///|
/// Tile (z, x, y): the clusters and points within the cluster radius of it,
/// in tile units of `extent`; None past `MAX_ZOOM` or where there are no trees
/// (geojson-vt's `getTile`).
pub fn ClusterIndex::tile(
  self : ClusterIndex,
  z : Int32,
  x : Int32,
  y : Int32,
) -> Array[ClusterFeature]? {
  if z < 0 || z > MAX_ZOOM {
    return None
  }
  guard self.tree_at(z) is Some(tree) else { return None }
  let o = self.options
  let z2 = pow2(z)
  let xd = x.to_double()
  let yd = y.to_double()
  if !o.wrap && (xd < 0.0 || xd >= z2 || yd < 0.0 || yd >= z2) {
    return None
  }
  let p = o.radius / o.extent.to_double()
  let top = encode_coord((yd - p) / z2)
  let bottom = encode_coord((yd + 1.0 + p) / z2)
  let out = []
  let left = encode_coord((xd - p) / z2)
  let right = encode_coord((xd + 1.0 + p) / z2)
  self.add_tile_features(
    out,
    tree.kd.range(left, top, right, bottom),
    tree,
    xd,
    yd,
    z2,
  )
  if o.wrap && xd == 0.0 {
    let ids = tree.kd.range(
      encode_coord(1.0 - p / z2),
      top,
      encode_coord(1.0),
      bottom,
    )
    self.add_tile_features(out, ids, tree, z2, yd, z2)
  }
  if o.wrap && xd == z2 - 1.0 {
    let ids = tree.kd.range(
      encode_coord(0.0),
      top,
      encode_coord(p / z2),
      bottom,
    )
    self.add_tile_features(out, ids, tree, -1.0, yd, z2)
  }
  Some(out)
}

///|
fn ClusterIndex::add_tile_features(
  self : ClusterIndex,
  out : Array[ClusterFeature],
  ids : Array[Int32],
  tree : ClusterTree,
  x : Double,
  y : Double,
  z2 : Double,
) -> Unit {
  let e = self.options.extent.to_double()
  for i in ids {
    let k = i * STRIDE
    let (px, py, row, cluster_id) = if tree.data[k + OFFSET_NUM] > 1 {
      (
        decode_coord(tree.coords[i * 2]),
        decode_coord(tree.coords[i * 2 + 1]),
        -1,
        tree.data[k + OFFSET_ID],
      )
    } else {
      let p = tree.data[k + OFFSET_ID]
      (self.xs[p], self.ys[p], self.rows[p], -1)
    }
    out.push({
      x: js_round(e * (px * z2 - x)).to_double(),
      y: js_round(e * (py * z2 - y)).to_double(),
      row,
      cluster_id,
      count: tree.data[k + OFFSET_NUM],
      props: self.props_of(tree.data, k),
    })
  }
}

///|
/// The zoom at which cluster `id` breaks apart (geojson-vt's
/// `getClusterExpansionZoom`, which does not check the id either).
pub fn ClusterIndex::expansion_zoom(self : ClusterIndex, id : Int32) -> Int32 {
  ((id.to_int64() - self.xs.length().to_int64()) % 32L).to_int()
}

///|
/// The clusters and points that cluster `id` is made of, one zoom down; None
/// if there is no such cluster (geojson-vt's `getChildren`).
pub fn ClusterIndex::children(
  self : ClusterIndex,
  id : Int32,
) -> Array[ClusterFeature]? {
  let origin = (id - self.xs.length()) >> 5
  let zoom = self.expansion_zoom(id)
  guard zoom >= 0 &&
    zoom < self.trees.length() &&
    self.trees[zoom] is Some(tree) &&
    origin >= 0 &&
    origin < tree.num_items else {
    return None
  }
  let o = self.options
  let r = o.radius / (o.extent.to_double() * pow2(zoom - 1)) * SCALE
  // Reused: leaves call this once per nested cluster.
  if self.found.length() < tree.num_items {
    self.found = FixedArray::make(tree.num_items, 0)
  }
  let found = self.found
  let n = tree.kd.within_into(
    tree.coords[origin * 2].to_double(),
    tree.coords[origin * 2 + 1].to_double(),
    r,
    found,
  )
  let children = []
  for j in 0..<n {
    let c = found[j]
    let k = c * STRIDE
    if tree.data[k + OFFSET_PARENT] != id {
      continue
    }
    if tree.data[k + OFFSET_NUM] > 1 {
      children.push({
        ..self.lng_lat(
          decode_coord(tree.coords[c * 2]),
          decode_coord(tree.coords[c * 2 + 1]),
          -1,
          tree.data[k + OFFSET_ID],
          tree.data[k + OFFSET_NUM],
        ),
        props: self.props_of(tree.data, k),
      })
    } else {
      let p = tree.data[k + OFFSET_ID]
      children.push(self.lng_lat(self.xs[p], self.ys[p], self.rows[p], -1, 1))
    }
  }
  if children.is_empty() {
    None
  } else {
    Some(children)
  }
}

///|
/// A feature at world (x, y), unprojected to longitude and latitude.
fn ClusterIndex::lng_lat(
  self : ClusterIndex,
  x : Double,
  y : Double,
  row : Int32,
  cluster_id : Int32,
  count : Int32,
) -> ClusterFeature {
  let y2 = (180.0 - y * 360.0) * @math.PI / 180.0
  {
    x: (x - 0.5) * 360.0,
    y: 360.0 * self.trig.atan(self.trig.exp(y2)) / @math.PI - 90.0,
    row,
    cluster_id,
    count,
    props: [],
  }
}

///|
/// Up to `limit` of the points in cluster `id` after skipping `offset` of
/// them (geojson-vt's `getLeaves`: a `limit` of 0 means 10, a negative one
/// no limit); None if there is no such cluster.
pub fn ClusterIndex::leaves(
  self : ClusterIndex,
  id : Int32,
  limit~ : Int32 = 10,
  offset~ : Int32 = 0,
) -> Array[ClusterFeature]? {
  let limit = if limit == 0 { 10 } else { limit }
  let out = []
  self.append_leaves(out, id, limit, offset, 0).map(_ => out)
}

///|
/// geojson-vt's `appendLeaves`: the points skipped so far, or None if a
/// cluster on the way does not exist.
fn ClusterIndex::append_leaves(
  self : ClusterIndex,
  out : Array[ClusterFeature],
  id : Int32,
  limit : Int32,
  offset : Int32,
  skipped : Int32,
) -> Int32? {
  guard self.children(id) is Some(children) else { return None }
  let mut skipped = skipped
  for child in children {
    if child.row < 0 {
      if skipped + child.count <= offset {
        skipped += child.count
      } else {
        guard self.append_leaves(out, child.cluster_id, limit, offset, skipped)
          is Some(s) else {
          return None
        }
        skipped = s
      }
    } else if skipped < offset {
      skipped += 1
    } else {
      out.push(child)
    }
    if out.length() == limit {
      break
    }
  }
  Some(skipped)
}

///|
/// geojson-vt's `point_count_abbreviated`: the count below 1000, else
/// thousands to one decimal ("1.5k") and, from 10000, whole ("12k").
fn abbreviated_count(count : Int32) -> @geom.Prop {
  if count >= 10000 {
    Str("\{js_round(count.to_double() / 1000.0)}k")
  } else if count >= 1000 {
    let r = js_round(count.to_double() / 100.0)
    if r % 10 == 0 {
      Str("\{r / 10}k")
    } else {
      Str("\{r / 10}.\{r % 10}k")
    }
  } else {
    Num(count.to_double())
  }
}
