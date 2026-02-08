#global internal

struct V {x, y, z: f32}
const A: [2] V = [{1, 2, 3}, {4, 5, 6}]
#assert(A[0].x == 1)
#assert(A[1].y == 5)

struct W {pos: V, weights: [3] f32}
const B: W = {{1, 2, 3}, [0.5, 1.5, 2.5]}
#assert(B.pos.z == 3)
#assert(#typeof(B) == W)

struct X {a: [2] V, b: [2] s32}
const C: X = {[{1, 2, 3}, {4, 5, 6}], [7, 8]}
#assert(#typeof(C) == X)

const D: [2] W = [{{1, 2, 3}, [1.0, 2.0, 3.0]}, {{4, 5, 6}, [4.0, 5.0, 6.0]}]
#assert(#typeof(D) == #type [2] W)

const E: W = {weights: [9.0, 8.0, 7.0], pos: {7, 8, 9}}
#assert(E.pos.y == 8)
#assert(#typeof(E) == W)
#assert(E.weights[1] == 8.0)