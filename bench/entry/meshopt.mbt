///|
let meshopt_modes : FixedArray[@meshopt.Mode] = [Attributes, Triangles, Indices]

///|
let meshopt_filters : FixedArray[@meshopt.Filter] = [
  NoFilter,
  Octahedral,
  Quaternion,
  Exponential,
  Color,
]

///|
/// `@meshopt.decode_gltf_buffer` of all of `source` into `target`; `mode` and `filter`
/// index `meshopt_modes` and `meshopt_filters` (the extension's strings in that order).
#export_name("meshopt_decode")
pub fn meshopt_decode(
  target : FixedArray[Byte],
  count : Int32,
  size : Int32,
  source : FixedArray[Byte],
  mode : Int32,
  filter : Int32,
) -> Bool {
  @meshopt.decode_gltf_buffer(
    target,
    count,
    size,
    source,
    0,
    source.length(),
    meshopt_modes[mode],
    meshopt_filters[filter],
  )
}
