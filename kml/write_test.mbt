///|
fn int_text(x : Double) -> String {
  x.to_int().to_string()
}

///|
test "write_kml writes placemarks as tokml does" {
  let b = @geom.TableBuilder::new()
  b.point(1, 2)
  b.end_ring()
  b.end_part()
  b.prop("note", Str("a<b&c"))
  b.prop("name", Str("東京\u{1}駅"))
  b.prop("visibility", Bool(false))
  b.prop("n", Num(3))
  b.end_feature(Point, id=Some(Str("p\"1")))
  b.prop("name", Num(0))
  b.prop("v", Null)
  b.end_feature(NoGeometry, id=Some(Num(7)))
  let kml = @kml.write_kml(b.finish(), number_text=int_text)
  assert_eq(
    kml,
    (
      #|<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
      #|<Placemark id="p&#x22;1">
      #|<name>東京駅</name><visibility>0</visibility><ExtendedData>
      #|  <Data name="note"><value>a&#x3C;b&#x26;c</value></Data>
      #|  <Data name="n"><value>3</value></Data></ExtendedData>
      #|  <Point><coordinates>1,2</coordinates></Point></Placemark>
      #|<Placemark id="7">
      #|<ExtendedData>
      #|  <Data name="v"><value>null</value></Data></ExtendedData>
      #|  </Placemark></Document></kml>
    ),
  )
}

///|
test "write_kml writes polygons and multi-geometries" {
  let b = @geom.TableBuilder::new()
  for k in 0..<2 {
    b.point(k.to_double(), 0)
    b.point(k.to_double(), 1)
    b.point(0, 0)
    b.end_ring()
  }
  b.end_part()
  b.end_feature(Polygon)
  for k in 0..<2 {
    b.point(k.to_double(), 5)
    b.point(6, 6)
    b.end_ring()
    b.end_part()
  }
  b.end_feature(MultiLineString)
  b.point(1, 1)
  b.point(2, 2)
  b.end_ring()
  b.end_part()
  b.end_feature(MultiPoint)
  let kml = @kml.write_kml(b.finish(), number_text=int_text)
  let want =
    #|<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
    #|<Placemark>
    #|<ExtendedData></ExtendedData>
    #|  <Polygon>
    #|<outerBoundaryIs>
    #|  <LinearRing><coordinates>0,0
    #|0,1
    #|0,0</coordinates></LinearRing></outerBoundaryIs>
    #|<innerBoundaryIs>
    #|  <LinearRing><coordinates>1,0
    #|1,1
    #|0,0</coordinates></LinearRing></innerBoundaryIs></Polygon></Placemark>
    #|<Placemark>
    #|<ExtendedData></ExtendedData>
    #|  <MultiGeometry>
    #|<LineString><coordinates>0,5
    #|6,6</coordinates></LineString>
    #|<LineString><coordinates>1,5
    #|6,6</coordinates></LineString></MultiGeometry></Placemark>
    #|<Placemark>
    #|<ExtendedData></ExtendedData>
    #|  <MultiGeometry>
    #|<Point><coordinates>1,1</coordinates></Point>
    #|<Point><coordinates>2,2</coordinates></Point></MultiGeometry></Placemark></Document></kml>
  assert_eq(kml, want)
}
