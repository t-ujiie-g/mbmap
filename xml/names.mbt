///|
/// Strings numbered in the order first added.
pub struct Names {
  priv keys : Array[String]
  priv ids : Map[String, Int32]
}

///|
pub fn Names::new() -> Names {
  { keys: [], ids: Map([]), }
}

///|
/// How many strings there are.
pub fn Names::length(self : Names) -> Int32 {
  self.keys.length()
}

///|
/// String `i`.
pub fn Names::at(self : Names, i : Int32) -> String {
  self.keys[i]
}

///|
/// The number of `s`, -1 if it was never added.
pub fn Names::find(self : Names, s : String) -> Int32 {
  self.ids.get(s).unwrap_or(-1)
}

///|
/// The number of `s`, added if new.
pub fn Names::add(self : Names, s : String) -> Int32 {
  match self.ids.get(s) {
    Some(id) => id
    None => {
      let id = self.keys.length()
      self.keys.push(s)
      self.ids[s] = id
      id
    }
  }
}
