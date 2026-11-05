///|
/// JavaScript's `Number(s)` for the decimal literals tests use (white space
/// trimmed, `""` is 0).
fn number(s : String) -> Double {
  let t = s.trim(chars=" \t\n\r").to_owned()
  if t == "" {
    return 0.0
  }
  @core.strconv_number(@utf8.encode(t)[:])
}

///|
fn number_text(x : Double) -> String {
  x.to_string()
}

///|
fn kml(s : String) -> @geom.Table raise @xml.XmlError {
  @kml.read_kml(
    @utf8.encode(s),
    number~,
    number_text~,
    trig=@core.Trig::moonbit(),
  )
}

///|
fn gpx(s : String) -> @geom.Table raise @xml.XmlError {
  @kml.read_gpx(@utf8.encode(s), number~, number_text~)
}

///|
/// A table's column `key` as a string per row (`-` where absent).
fn column(t : @geom.Table, key : String) -> Array[String] {
  match t.column(key) {
    Some(c) =>
      c.values.map(v => {
        match v {
          None => "-"
          Some(Str(s)) => s
          Some(Num(n)) => n.to_string()
          Some(Bool(b)) => b.to_string()
          Some(Null) => "null"
        }
      })
    None => []
  }
}

///|
fn doc(body : String) -> String {
  "<kml xmlns=\"http://www.opengis.net/kml/2.2\" xmlns:gx=\"http://www.google.com/kml/ext/2.2\"><Document>" +
  body +
  "</Document></kml>"
}

///|
test "a point placemark with its name and id" {
  let t = kml(
    doc(
      "<Placemark id=\"a\"><name>A</name><Point><coordinates>139.7671,35.6812,0</coordinates></Point></Placemark>",
    ),
  )
  assert_eq(t.kinds, [Point])
  assert_eq(t.coords, [139.7671, 35.6812])
  assert_eq(column(t, "name"), ["A"])
  assert_eq(t.ids, [Some(Str("a"))])
}

///|
test "lines, rings and polygons as togeojson reads their tuples" {
  let t = kml(
    doc(
      "<Placemark><LineString><coordinates>0,0 1, 1 2,2,5</coordinates></LineString></Placemark>" +
      "<Placemark><Polygon><outerBoundaryIs><LinearRing><coordinates>0,0 4,0 4,4</coordinates></LinearRing></outerBoundaryIs>" +
      "<innerBoundaryIs><LinearRing><coordinates>1,1 2,1</coordinates></LinearRing></innerBoundaryIs></Polygon></Placemark>" +
      "<Placemark><LinearRing><coordinates>0,0 1,0 0,0</coordinates></LinearRing></Placemark>",
    ),
  )
  assert_eq(t.kinds, [LineString, Polygon, LineString])
  // `1, 1` splits into `1,` and `1`, neither a tuple; the ring is closed (fixRing) and
  // the hole, too short, left out.
  assert_eq(t.coords, [
    0.0, 0.0, 2.0, 2.0, 0.0, 0.0, 4.0, 0.0, 4.0, 4.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0,
    0.0, 0.0,
  ])
  assert_eq(t.ring_ends, [1, 2, 3])
}

///|
test "a multi-geometry gives a row per member with the same properties" {
  let t = kml(
    doc(
      "<Placemark><name>m</name><MultiGeometry><Point><coordinates>1,2</coordinates></Point>" +
      "<MultiGeometry><Point><coordinates>Infinity,2</coordinates></Point><Point><coordinates>3,4</coordinates></Point></MultiGeometry>" +
      "</MultiGeometry></Placemark><Placemark><name>none</name></Placemark>",
    ),
  )
  assert_eq(t.kinds, [Point, Point, NoGeometry])
  assert_eq(t.coords, [1.0, 2.0, 3.0, 4.0])
  assert_eq(column(t, "name"), ["m", "m", "none"])
}

///|
test "tracks: coords, a point for one, times as coordinateProperties" {
  let t = kml(
    doc(
      "<Placemark><gx:MultiTrack><gx:Track><when>a</when><when>b</when><gx:coord>1 2 3</gx:coord><gx:coord>4 5</gx:coord></gx:Track>" +
      "<gx:Track><when>c</when><gx:coord>6 7</gx:coord></gx:Track></gx:MultiTrack></Placemark>" +
      "<Placemark><Track><coord>1  2</coord><coord>3 4</coord></Track></Placemark>",
    ),
  )
  assert_eq(t.kinds, [LineString, Point, NoGeometry])
  assert_eq(t.coords, [1.0, 2.0, 4.0, 5.0, 6.0, 7.0])
  assert_eq(column(t, "coordinateProperties"), [
    "{\"times\":[[\"a\",\"b\"],[\"c\"]]}", "{\"times\":[[\"a\",\"b\"],[\"c\"]]}",
    "-",
  ])
}

///|
test "styles resolved through ids, style maps and inline styles" {
  let t = kml(
    doc(
      "<Style id=\"s\"><LineStyle><color>7f0000ff</color><width>3</width></LineStyle><PolyStyle><fill>0</fill><outline>0</outline></PolyStyle></Style>" +
      "<StyleMap id=\"m\"><Pair><key>normal</key><styleUrl>#s</styleUrl></Pair></StyleMap>" +
      "<Placemark><styleUrl>m</styleUrl></Placemark>" +
      "<Placemark><Style><IconStyle><color>#ffffff</color><scale>2</scale><hotSpot x=\"1\" y=\"0.5\" xunits=\"pixels\"/><Icon><href>i.png</href></Icon></IconStyle><LabelStyle><color>zz000000</color></LabelStyle></Style></Placemark>",
    ),
  )
  assert_eq(column(t, "styleUrl"), ["#m", "-"])
  assert_eq(column(t, "stroke"), ["#ff0000", "-"])
  assert_eq(column(t, "stroke-opacity"), [(127.0 / 255.0).to_string(), "-"])
  assert_eq(column(t, "stroke-width"), ["3", "-"])
  assert_eq(column(t, "fill-opacity"), ["0", "-"])
  assert_eq(column(t, "icon-color"), ["-", "#ffffff"])
  assert_eq(column(t, "icon-scale"), ["-", "2"])
  assert_eq(column(t, "icon-offset"), ["-", "[1,0.5]"])
  assert_eq(column(t, "icon-offset-units"), ["-", "[\"pixels\",\"\"]"])
  assert_eq(column(t, "icon"), ["-", "i.png"])
  assert_eq(column(t, "label-color"), ["-", "#000000"])
  assert_eq(column(t, "label-opacity"), ["-", "NaN"])
}

///|
test "extended data typed by its schema, visibility, times and descriptions" {
  let t = kml(
    doc(
      "<Schema><SimpleField name=\"n\" type=\"int\"/><SimpleField name=\"b\" type=\"bool\"/></Schema>" +
      "<Placemark><name>x</name><visibility>1</visibility><description><![CDATA[<b>x</b>]]></description>" +
      "<ExtendedData><Data name=\"name\"><value>y</value></Data><Data name=\"__proto__\"><value>p</value></Data>" +
      "<SchemaData><SimpleData name=\"n\">12</SimpleData><SimpleData name=\"b\">false</SimpleData><SimpleData name=\"s\">007</SimpleData></SchemaData></ExtendedData>" +
      "<TimeSpan><begin>2020</begin></TimeSpan><TimeStamp><when>2021</when></TimeStamp></Placemark>" +
      "<Placemark><visibility>0</visibility><description>a&amp;b&#1114112;</description></Placemark>",
    ),
  )
  assert_eq(column(t, "name"), ["y", "-"])
  assert_eq(column(t, "n"), ["12", "-"])
  assert_eq(column(t, "b"), ["true", "-"])
  assert_eq(column(t, "s"), ["007", "-"])
  assert_eq(column(t, "visibility"), ["true", "false"])
  assert_eq(column(t, "description"), [
    "{\"@type\":\"html\",\"value\":\"<b>x</b>\"}", "a&b\u{FFFD}\u{FFFD}",
  ])
  assert_eq(column(t, "timespan"), ["{\"begin\":\"2020\",\"end\":\"\"}", "-"])
  assert_eq(column(t, "timestamp"), ["2021", "-"])
  assert_true(t.column("__proto__") is None)
}

///|
test "ground overlays: boxes, turned boxes and quads" {
  let t = kml(
    doc(
      "<GroundOverlay><name>g</name><Icon><href>a.png</href></Icon><LatLonBox><north>2</north><south>0</south><east>2</east><west>0</west><rotation>90</rotation></LatLonBox></GroundOverlay>" +
      "<GroundOverlay><gx:LatLonQuad><coordinates>0,0 1,0 1,1 0,1</coordinates></gx:LatLonQuad></GroundOverlay>" +
      "<GroundOverlay><LatLonBox><north>x</north></LatLonBox></GroundOverlay>" +
      "<NetworkLink><name>left out</name></NetworkLink>",
    ),
  )
  assert_eq(t.kinds, [Polygon, Polygon, NoGeometry])
  assert_eq(column(t, "@geometry-type"), [
    "groundoverlay", "groundoverlay", "groundoverlay",
  ])
  assert_eq(column(t, "icon"), ["a.png", "-", "-"])
  // Turned by 90°: the north-west corner goes to the south-west.
  assert_true(
    (t.coords[0] - 0.0).abs() < 1.0e-12 && (t.coords[1] - 0.0).abs() < 1.0e-12,
  )
  assert_eq(t.coords.length(), 5 * 2 + 5 * 2)
}

///|
test "malformed KML raises XmlError" {
  let msg = try kml("<kml><Placemark></kml>") catch {
    e => e.message()
  } noraise {
    _ => ""
  }
  assert_eq(
    msg, "malformed XML at 16: opening and ending tag mismatch: Placemark != kml",
  )
  assert_eq(kml("<other/>").length(), 0)
}

///|
test "GPX tracks, routes and waypoints" {
  let ns = " xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\""
  let t = gpx(
    "<gpx" +
    ns +
    "><wpt lat=\"1\" lon=\"2\"><ele>5</ele><name>w</name><sym>s</sym><link href=\"h\"><text>t</text></link></wpt>" +
    "<rte><rtept lat=\"1\" lon=\"1\"/><rtept lat=\"2\" lon=\"2\"/><extensions><line><color>ff0000</color><width>1</width></line></extensions></rte>" +
    "<trk><name>t</name><trkseg><trkpt lat=\"1\" lon=\"1\"><time>a</time><extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>90</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions></trkpt>" +
    "<trkpt lat=\"x\" lon=\"1\"/><trkpt lat=\"2\" lon=\"2\"><extensions><cad>3</cad></extensions></trkpt></trkseg>" +
    "<trkseg><trkpt lat=\"3\" lon=\"3\"/><trkpt lat=\"4\" lon=\"4\"/></trkseg><trkseg><trkpt lat=\"5\" lon=\"5\"/></trkseg></trk></gpx>",
  )
  assert_eq(t.kinds, [MultiLineString, LineString, Point])
  assert_eq(column(t, "_gpxType"), ["trk", "rte", "-"])
  assert_eq(column(t, "name"), ["t", "-", "w"])
  assert_eq(column(t, "time"), ["a", "-", "-"])
  assert_eq(column(t, "gpxtpx_hr"), ["90", "-", "-"])
  assert_eq(column(t, "coordinateProperties"), [
    "{\"times\":[[\"a\"]],\"heart\":[[90,null,null],[null,null]],\"cads\":[[null,null,3],[null,null]]}",
    "-", "-",
  ])
  assert_eq(column(t, "stroke"), ["-", "#ff0000", "-"])
  assert_eq(column(t, "stroke-width"), ["-", (96.0 / 25.4).to_string(), "-"])
  assert_eq(column(t, "links"), ["-", "-", "[{\"href\":\"h\",\"text\":\"t\"}]"])
  assert_eq(column(t, "sym"), ["-", "-", "s"])
  assert_eq(t.coords[0:4].to_owned(), [1.0, 1.0, 2.0, 2.0])
}

///|
test "malformed GPX raises XmlError" {
  let failed = try gpx("<gpx><wpt></gpx>") catch {
    Malformed(_, ..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(failed)
  assert_eq(gpx("<gpx/>").length(), 0)
}

///|
test "parse_float is JavaScript's parseFloat" {
  let n = s => @kml.parse_float(s, number)
  assert_eq(n("  -1.5e2xyz"), -150.0)
  assert_eq(n(".5"), 0.5)
  assert_eq(n("5."), 5.0)
  assert_eq(n("+Infinity!"), @double.infinity)
  assert_eq(n("-Infinity"), @double.neg_infinity)
  assert_eq(n("1e"), 1.0)
  assert_eq(n("1e+x"), 1.0)
  assert_eq(n("0.1234567890123456789"), 0.1234567890123456789)
  assert_eq(n("123456789012345678x"), 123456789012345678.0)
  assert_true(n("").is_nan())
  assert_true(n(".").is_nan())
  assert_true(n("-").is_nan())
  assert_true(n("infinity").is_nan())
  assert_eq(1.0 / n("-0"), @double.neg_infinity)
}

///|
test "a feature past MAX_KML_KEYS properties is refused" {
  let data = StringBuilder()
  for i in 0..<@kml.MAX_KML_KEYS {
    data.write_string("<Data name=\"k\{i}\"><value>v</value></Data>")
  }
  let at_limit = kml(
    doc(
      "<Placemark><ExtendedData>" +
      data.to_string() +
      "</ExtendedData></Placemark>",
    ),
  )
  assert_eq(at_limit.columns.length(), @kml.MAX_KML_KEYS)
  let msg = try
    kml(
      doc(
        "<Placemark><name>x</name><ExtendedData>" +
        data.to_string() +
        "</ExtendedData></Placemark>",
      ),
    )
  catch {
    e => e.message()
  } noraise {
    _ => ""
  }
  assert_eq(msg, "too large: more than 4096 properties in a feature")
}
