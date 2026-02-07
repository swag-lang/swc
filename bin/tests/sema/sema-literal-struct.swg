#global internal

const A = {1's32, 2}

struct V {x, y, z: f32}
const v: V = {10, 5, 2}
#assert(v.x == 10)
#assert(v.y == 5)
#assert(v.z == 2)
#assert(#typeof(v) == V)

const v1 = {10, 5, 2}
#assert(v1.x == 10)
#assert(v1.y == 5)
#assert(v1.z == 2)
