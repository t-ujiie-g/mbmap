// Imported packages' `#export_name`s are not exported, so both entry points are
// re-exported here. Their inputs share an address: use one at a time.

///|
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  @worker.prepare_input(len)
}

///|
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  @worker.output_addr()
}

///|
#export_name("init_style")
pub fn init_style() -> Int32 {
  @worker.init_style()
}

///|
#export_name("process_tile")
pub fn process_tile(source : Int32, z : Int32, x : Int32, y : Int32) -> Int32 {
  @worker.process_tile(source, z, x, y)
}

///|
#export_name("analyze")
pub fn analyze(n_rings : Int32, n_polys : Int32, n_points : Int32) -> Int32 {
  @analysis_entry.analyze(n_rings, n_polys, n_points)
}

///|
#export_name("prepare_analysis_input")
pub fn prepare_analysis_input(len : Int32) -> Int32 {
  @analysis_entry.prepare_input(len)
}
