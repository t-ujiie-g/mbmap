///|
extern "js" fn i16_buffer(values : FixedArray[Int32]) -> JsBuffer =
  #|(v) => Int16Array.from(v).buffer

///|
test "extrusion_runs lists each run of vertices sharing a centroid" {
  // Four 12-short vertices (24 bytes); centroids at shorts 6 and 7.
  let vertex = (cx : Int32, cy : Int32) => {
    [0, 0, 0, 0, 0, 0, cx, cy, 0, 0, 0, 0]
  }
  let v = [..vertex(5, 6), ..vertex(5, 6), ..vertex(7, 6), ..vertex(5, 6)]
  let runs = extrusion_runs(i16_buffer(FixedArray::from_array(v)))
  assert_eq(Array::from_fixed_array(runs), [0, 5, 6, 2, 7, 6, 3, 5, 6])
  assert_eq(extrusion_runs(i16_buffer([])).length(), 0)
}
