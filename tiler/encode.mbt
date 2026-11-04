///|
/// The tile as bytes for the display worker (docs/FORMATS.md, "Columnar
/// tile"), with properties and ids from `table`'s rows, and line metrics as
/// geojson-vt's `CLIP_START` and `CLIP_END` properties.
pub fn encode_tile(d : TileData, table : @geom.Table) -> Bytes {
  let w = @core.ByteWriter::new()
  let columns = table.columns.filter(c => {
    c.name != CLIP_START &&
    c.name != CLIP_END &&
    d.rows.iter().any(row => c.values[row] is Some(_))
  })
  let metrics = d.clips.length() > 0
  w.u32(d.types.length())
  w.u32(d.point_ends.length())
  w.u32(d.xy.length() / 2)
  w.u32(columns.length() + (if metrics { 2 } else { 0 }))
  for t in d.types {
    w.u8(t)
  }
  w.pad4()
  for e in d.ring_ends {
    w.u32(e)
  }
  for e in d.point_ends {
    w.u32(e)
  }
  for v in d.xy {
    w.i16(v)
  }
  w.pad4()
  for c in columns {
    w.utf8(c.name)
  }
  if metrics {
    w.utf8(CLIP_START)
    w.utf8(CLIP_END)
  }
  for c in columns {
    for row in d.rows {
      @geom.write_prop(w, c.values[row])
    }
  }
  if metrics {
    for k in 0..<2 {
      for f in 0..<d.rows.length() {
        let v = d.clips[f * 2 + k]
        let p : @geom.Prop? = if v.is_nan() { None } else { Some(Num(v)) }
        @geom.write_prop(w, p)
      }
    }
  }
  for row in d.rows {
    @geom.write_prop(w, table.ids[row])
  }
  w.to_bytes()
}

///|
/// The properties line metrics add to a line feature (geojson-vt's names): the
/// shares of its line's length where the feature starts and ends.
pub const CLIP_START : String = "geojsonvt_clip_start"

///|
pub const CLIP_END : String = "geojsonvt_clip_end"

///|
/// The keys a cluster has (geojson-vt's `getClusterProperties`).
let cluster_keys : Array[String] = [
  "cluster", "cluster_id", "point_count", "point_count_abbreviated",
]

///|
/// Property `key` of `f`: a point's from `table`, a cluster's its own (then its
/// cluster properties').
fn cluster_prop(
  f : ClusterFeature,
  key : String,
  table : @geom.Table,
) -> @geom.Prop? {
  if f.row >= 0 {
    return table.column(key).bind(c => c.values[f.row])
  }
  match key {
    "cluster" => Some(Bool(true))
    "cluster_id" => Some(Num(f.cluster_id.to_double()))
    "point_count" => Some(Num(f.count.to_double()))
    "point_count_abbreviated" => Some(abbreviated_count(f.count))
    _ => f.props.search_by(p => p.0 == key).map(k => f.props[k].1)
  }
}

///|
/// The id of `f`: a point's from `table`, a cluster's its cluster id.
fn cluster_feature_id(f : ClusterFeature, table : @geom.Table) -> @geom.Prop? {
  if f.row >= 0 {
    table.ids[f.row]
  } else {
    Some(Num(f.cluster_id.to_double()))
  }
}

///|
/// A tile of `ClusterIndex::tile` as bytes for the display worker
/// (docs/FORMATS.md, "Columnar tile"): a feature per point or cluster.
pub fn encode_cluster_tile(
  fs : Array[ClusterFeature],
  table : @geom.Table,
) -> Bytes {
  let keys = table.columns
    .filter(c => fs.iter().any(f => f.row >= 0 && c.values[f.row] is Some(_)))
    .map(c => c.name)
  for f in fs {
    for p in f.props {
      if !keys.contains(p.0) {
        keys.push(p.0)
      }
    }
  }
  if fs.iter().any(f => f.row < 0) {
    for k in cluster_keys {
      if !keys.contains(k) {
        keys.push(k)
      }
    }
  }
  let w = @core.ByteWriter::new()
  w.u32(fs.length())
  w.u32(fs.length())
  w.u32(fs.length())
  w.u32(keys.length())
  for _ in fs {
    w.u8(@core.GEOM_POINTS)
  }
  w.pad4()
  for i in 1..<=fs.length() {
    w.u32(i)
  }
  for i in 1..<=fs.length() {
    w.u32(i)
  }
  for f in fs {
    w.i16(f.x.to_int())
    w.i16(f.y.to_int())
  }
  w.pad4()
  for k in keys {
    w.utf8(k)
  }
  for k in keys {
    for f in fs {
      @geom.write_prop(w, cluster_prop(f, k, table))
    }
  }
  for f in fs {
    @geom.write_prop(w, cluster_feature_id(f, table))
  }
  w.to_bytes()
}

///|
/// What `ClusterIndex::children` and `leaves` give, as docs/FORMATS.md's
/// "Cluster features".
pub fn encode_cluster_features(
  fs : Array[ClusterFeature],
  table : @geom.Table,
) -> Bytes {
  let w = @core.ByteWriter::new()
  w.u32(fs.length())
  for f in fs {
    w.f64(f.x)
    w.f64(f.y)
    @geom.write_prop(w, cluster_feature_id(f, table))
    let props = []
    if f.row >= 0 {
      for c in table.columns {
        if c.values[f.row] is Some(v) {
          props.push((c.name, v))
        }
      }
    } else {
      for p in f.props {
        if !cluster_keys.contains(p.0) {
          props.push(p)
        }
      }
      for k in cluster_keys {
        props.push((k, cluster_prop(f, k, table).unwrap()))
      }
    }
    w.u32(props.length())
    for p in props {
      w.utf8(p.0)
      @geom.write_prop(w, Some(p.1))
    }
  }
  w.to_bytes()
}
