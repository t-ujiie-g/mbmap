///|
fn esri(text : String) -> (@geom.Table, Bool) raise {
  let b = @utf8.encode(text)
  @formats.read_esri_json(b[:], slow_number=(s, e) => {
    @core.strconv_number(b[s:e])
  })
}

///|
fn esri_error(text : String) -> String {
  try esri(text) catch {
    @formats.ReadError::Invalid(_) as e => e.message()
    _ => "other error"
  } noraise {
    _ => "read"
  }
}

///|
fn flat(t : @geom.Table, feature : Int32) -> Array[Double] {
  let (p0, p1) = t.parts(feature)
  let (s, _) = t.points(t.rings(p0).0)
  let (_, e) = t.points(t.rings(p1 - 1).1 - 1)
  t.coords[s * 2:e * 2].to_owned()
}

///|
let feature_set : String =
  #|{"objectIdFieldName": "FID", "exceededTransferLimit": true, "features": [
  #| {"attributes": {"FID": 7, "name": "a"}, "geometry": {"x": 139.5, "y": 35.5, "spatialReference": {"wkid": 4326}}},
  #| {"attributes": {"OBJECTID": "x"}, "geometry": {"points": [[1, 2], [3, 4, 5]]}},
  #| {"geometry": {"paths": [[[0, 0], [1, 1]]]}},
  #| {"geometry": {"paths": [[[0, 0], [1, 1]], [[2, 2], [3, 3]]]}},
  #| {"geometry": {"rings": [[[0, 0], [0, 10], [10, 10], [10, 0], [0, 0]], [[2, 2], [4, 2], [4, 4], [2, 4], [2, 2]]]}},
  #| {"geometry": {"rings": [[[0, 0], [0, 1], [1, 1], [1, 0]], [[5, 5], [5, 6], [6, 6], [6, 5], [5, 5]]]}},
  #| {"geometry": {"xmin": 0, "ymin": 1, "xmax": 2, "ymax": 3, "rings": [[[9, 9], [9, 8], [8, 8], [9, 9]]]}},
  #| {"attributes": {"FID": null}, "geometry": null}
  #|]}

///|
test "an Esri feature set read as arcgisToGeoJSON makes GeoJSON of it" {
  let (t, exceeded) = esri(feature_set)
  assert_true(exceeded)
  assert_eq(t.kinds, [
    Point,
    MultiPoint,
    LineString,
    MultiLineString,
    Polygon,
    MultiPolygon,
    Polygon,
    NoGeometry,
  ])
  assert_eq(t.ids, [
    Some(Num(7.0)),
    Some(Str("x")),
    None,
    None,
    None,
    None,
    None,
    None,
  ])
  assert_eq(flat(t, 0), [139.5, 35.5])
  assert_eq(flat(t, 1), [1.0, 2.0, 3.0, 4.0])
  assert_eq(flat(t, 3), [0.0, 0.0, 1.0, 1.0, 2.0, 2.0, 3.0, 3.0])
  // Outer rings wound counter-clockwise, holes clockwise and given to their outer ring.
  assert_eq(flat(t, 4), [
    0.0, 0.0, 10.0, 0.0, 10.0, 10.0, 0.0, 10.0, 0.0, 0.0, 2.0, 2.0, 2.0, 4.0, 4.0,
    4.0, 4.0, 2.0, 2.0, 2.0,
  ])
  let (r0, r1) = t.rings(t.parts(4).0)
  assert_eq(r1 - r0, 2)
  // An open ring is closed.
  assert_eq(flat(t, 5), [
    0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 5.0, 5.0, 6.0, 5.0, 6.0, 6.0,
    5.0, 6.0, 5.0, 5.0,
  ])
  // An envelope wins over rings.
  assert_eq(flat(t, 6), [2.0, 3.0, 0.0, 3.0, 0.0, 1.0, 2.0, 1.0, 2.0, 3.0])
  assert_eq(t.column("FID").unwrap().values, [
    Some(Num(7.0)),
    None,
    None,
    None,
    None,
    None,
    None,
    Some(Null),
  ])
  assert_eq(t.column("name").unwrap().values[0], Some(Str("a")))
}

///|
test "Esri holes outside every outer ring cross one or become outer rings" {
  let (t, exceeded) = esri(
    "{\"features\":[{\"attributes\":{\"FID\":\"f\",\"OBJECTID\":3},\"geometry\":{\"rings\":[[[0,0],[0,4],[4,4],[4,0],[0,0]],[[3,1],[6,1],[6,3],[3,3],[3,1]],[[10,10],[12,10],[12,12],[10,12],[10,10]],[[0,0],[1,0],[0,0]]]}}]}",
  )
  assert_false(exceeded)
  assert_eq(t.ids, [Some(Num(3.0))])
  assert_eq(t.kinds, [MultiPolygon])
  // The crossing hole goes to the outer ring, the free one becomes a polygon of its own,
  // wound as it was given; the two-point ring is dropped.
  assert_eq(t.parts(0), (0, 2))
  assert_eq(t.rings(0), (0, 2))
  let (s, e) = t.points(1)
  assert_eq(t.coords[s * 2:e * 2].to_owned(), [
    3.0, 1.0, 3.0, 3.0, 6.0, 3.0, 6.0, 1.0, 3.0, 1.0,
  ])
  let (s, e) = t.points(2)
  assert_eq(t.coords[s * 2:e * 2].to_owned(), [
    10.0, 10.0, 12.0, 10.0, 12.0, 12.0, 10.0, 12.0, 10.0, 10.0,
  ])
}

///|
test "malformed Esri JSON is refused" {
  assert_eq(
    esri_error("{}"),
    "malformed ArcGIS JSON at 0: not an ArcGIS feature set",
  )
  assert_eq(
    esri_error("{\"error\":{\"code\":400,\"message\":\"Invalid query\"}}"),
    "malformed ArcGIS JSON at 9: ArcGIS error: Invalid query",
  )
  assert_eq(
    esri_error("{\"error\":3}"),
    "malformed ArcGIS JSON at 9: ArcGIS error: ",
  )
  assert_eq(
    esri_error("{\"features\":[]} x"),
    "malformed ArcGIS JSON at 16: unexpected data after the feature set",
  )
  assert_eq(
    esri_error("{\"features\":[3]}"),
    "malformed ArcGIS JSON at 13: expected a feature",
  )
  assert_eq(
    esri_error("{\"features\":[{\"geometry\":{\"points\":[[1]]}}]}"),
    "malformed ArcGIS JSON at 39: a position needs x and y",
  )
  assert_eq(
    esri_error("{\"features\":{}}"),
    "malformed ArcGIS JSON at 12: expected '['",
  )
}

///|
fn pbf_message(f : (@pbf.Writer) -> Unit) -> Bytes {
  let w = @pbf.Writer::new()
  f(w)
  w.to_bytes()
}

///|
fn pbf_field(w : @pbf.Writer, field : Int32, inner : Bytes) -> Unit {
  w.write_tag(field, @pbf.WIRE_LEN)
  w.write_bytes(inner[:])
}

///|
fn pbf_double(w : @pbf.Writer, field : Int32, v : Double) -> Unit {
  w.write_tag(field, @pbf.WIRE_FIXED64)
  w.write_fixed64(v.reinterpret_as_uint64())
}

///|
/// A query result of `geometry_type` with `head` written first in its `FeatureResult`,
/// fields `OID`, `name` and `v`, scale (0.5, 0.25), translate (100, 10) and `features`.
fn pbf_result(
  geometry_type : Int32,
  features : Array[Bytes],
  head~ : (@pbf.Writer) -> Unit = _ => (),
) -> Bytes {
  let result = pbf_message(w => {
    head(w)
    w.write_tag(1, @pbf.WIRE_LEN)
    w.write_string("OID")
    // As proto3 writes it: a point result has no geometry type.
    if geometry_type != 0 {
      w.write_tag(7, @pbf.WIRE_VARINT)
      w.write_varint32(geometry_type)
    }
    let transform = pbf_message(t => {
      pbf_field(
        t,
        2,
        pbf_message(s => {
          pbf_double(s, 1, 0.5)
          pbf_double(s, 2, 0.25)
        }),
      )
      pbf_field(
        t,
        3,
        pbf_message(s => {
          pbf_double(s, 1, 100.0)
          pbf_double(s, 2, 10.0)
        }),
      )
    })
    pbf_field(w, 12, transform)
    for name in ["OID", "name", "v"] {
      pbf_field(
        w,
        13,
        pbf_message(f => {
          f.write_tag(1, @pbf.WIRE_LEN)
          f.write_string(name)
        }),
      )
    }
    for f in features {
      pbf_field(w, 15, f)
    }
  })
  pbf_message(w => pbf_field(w, 2, pbf_message(q => pbf_field(q, 1, result))))
}

///|
/// A feature of `attributes` (written as they are) and a geometry of `lengths` and
/// `coords`, packed.
fn pbf_feature(
  attributes : Array[(@pbf.Writer) -> Unit],
  lengths : Array[Int32],
  coords : Array[Int64],
) -> Bytes {
  pbf_message(w => {
    for a in attributes {
      pbf_field(w, 1, pbf_message(a))
    }
    if coords.length() > 0 {
      pbf_field(
        w,
        2,
        pbf_message(g => {
          pbf_field(
            g,
            2,
            pbf_message(p => {
              for n in lengths {
                p.write_varint32(n)
              }
            }),
          )
          pbf_field(
            g,
            3,
            pbf_message(p => {
              for c in coords {
                p.write_sint64(c)
              }
            }),
          )
        }),
      )
    }
  })
}

///|
fn esri_pbf_error(bytes : Bytes) -> String {
  try @formats.read_esri_pbf(bytes[:]) catch {
    @formats.ReadError::Invalid(_) as e => e.message()
  } noraise {
    _ => "read"
  }
}

///|
test "an Esri PBF query result read as its JSON: quantized, delta-coded, y down" {
  let ring = pbf_feature(
    [
      w => {
        w.write_tag(4, @pbf.WIRE_VARINT)
        w.write_svarint32(5)
      },
      w => {
        w.write_tag(1, @pbf.WIRE_LEN)
        w.write_string("a")
      },
      w => pbf_double(w, 3, 1.5),
    ],
    [5],
    [0L, 0L, 0L, -4L, 4L, 0L, 0L, 4L, -4L, 0L],
  )
  let none = pbf_feature(
    [
      w => {
        w.write_tag(5, @pbf.WIRE_VARINT)
        w.write_varint32(6)
      },
      w => {
        w.write_tag(2, @pbf.WIRE_FIXED32)
        w.write_fixed32((0.5 : Float).reinterpret_as_uint())
      },
      w => {
        w.write_tag(9, @pbf.WIRE_VARINT)
        w.write_varint32(1)
      },
      w => {
        w.write_tag(6, @pbf.WIRE_VARINT)
        w.write_varint(18446744073709551615UL)
      },
    ],
    [],
    [],
  )
  let bytes = pbf_result(3, [ring, none], head=w => {
    w.write_tag(9, @pbf.WIRE_VARINT)
    w.write_varint32(1)
  })
  let (t, exceeded) = @formats.read_esri_pbf(bytes[:])
  assert_true(exceeded)
  assert_eq(t.kinds, [Polygon, NoGeometry])
  assert_eq(t.ids, [Some(Num(5.0)), Some(Num(6.0))])
  assert_eq(t.coords, [
    100.0, 10.0, 102.0, 10.0, 102.0, 11.0, 100.0, 11.0, 100.0, 10.0,
  ])
  assert_eq(t.column("name").unwrap().values, [Some(Str("a")), Some(Num(0.5))])
  assert_eq(t.column("v").unwrap().values, [Some(Num(1.5)), Some(Bool(true))])
  assert_eq(t.columns.length(), 3)
}

///|
test "Esri PBF points, lines and multipoints, with Z and M and a lower-left origin" {
  let lower_left = (w : @pbf.Writer) => {
    w.write_tag(10, @pbf.WIRE_VARINT)
    w.write_varint32(1)
    w.write_tag(11, @pbf.WIRE_VARINT)
    w.write_varint32(1)
    w.write_tag(12, @pbf.WIRE_LEN)
    w.write_bytes(
      pbf_message(t => {
        t.write_tag(1, @pbf.WIRE_VARINT)
        t.write_varint32(1)
      })[:],
    )
  }
  let point = pbf_feature([], [1], [2L, 3L, 9L, 8L])
  let (t, exceeded) = @formats.read_esri_pbf(
    pbf_result(0, [point], head=lower_left)[:],
  )
  assert_false(exceeded)
  assert_eq((t.kinds, t.coords), ([Point], [101.0, 10.75]))
  let line = pbf_feature([], [2, 2], [
    0L, 0L, 1L, 1L, 2L, 4L, 0L, 0L, 6L, 4L, 0L, 0L, -2L, -4L, 0L, 0L,
  ])
  let (t, _) = @formats.read_esri_pbf(pbf_result(2, [line], head=lower_left)[:])
  assert_eq(t.kinds, [MultiLineString])
  assert_eq(t.coords, [100.0, 10.0, 101.0, 11.0, 103.0, 11.0, 102.0, 10.0])
  let one = pbf_feature([], [2], [0L, 0L, 2L, 4L])
  let (t, _) = @formats.read_esri_pbf(pbf_result(2, [one, one])[:])
  assert_eq(t.kinds, [LineString, LineString])
  assert_eq(t.coords, [100.0, 10.0, 101.0, 9.0, 100.0, 10.0, 101.0, 9.0])
  let (t, _) = @formats.read_esri_pbf(pbf_result(1, [one])[:])
  assert_eq((t.kinds, t.coords), ([MultiPoint], [100.0, 10.0, 101.0, 9.0]))
}

///|
test "malformed Esri PBF is refused" {
  assert_eq(
    esri_pbf_error(b""),
    "malformed ArcGIS PBF at 0: not an ArcGIS query result",
  )
  let good = pbf_result(3, [pbf_feature([], [5], [0L, 0L, 0L, 1L, 1L, 0L])])
  assert_true(esri_pbf_error(good).has_suffix("malformed geometry"))
  let cut = good[:good.length() - 1].to_owned()
  assert_true(esri_pbf_error(cut).has_suffix("malformed protocol buffers"))
  let point = pbf_result(0, [pbf_feature([], [1], [1L])])
  assert_true(esri_pbf_error(point).has_suffix("malformed geometry"))
  let negative = pbf_result(2, [pbf_feature([], [-1], [1L, 1L])])
  assert_true(esri_pbf_error(negative).has_suffix("malformed geometry"))
}
