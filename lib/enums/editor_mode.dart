enum EditorMode {
  view,   // Just looking at the map
  create, // Drawing a new line
  edit,   // Moving points (General edit mode)
  cut,    // Cutting lines
  join,   // Joining lines
  extend, // extending a line
  reverse, // reversing a line
  deletePoint,
  createWaypoint
}