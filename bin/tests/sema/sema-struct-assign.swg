#global internal

struct V {x, y, z: f32}

const v: V = {10, 5}
#assert(v.x == 10)
#assert(v.y == 5)
#assert(v.z == 0)

