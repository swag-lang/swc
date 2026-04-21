#global fileprivate

const A = 52
const B = A
#assert(B == 52)

fileprivate
{
    const C = A + 10
    #assert(C == 62)
}

fileprivate const D = A * 2
#assert(D == 104)

const V0 = 1
const V1 = 1.0
#assert(#typeof(V1) == f32)
const V2 = 0x1FFFFFFFF
#assert(#typeof(V2) == u64)
const V3 = 10000000000000000000.0
#assert(#typeof(V3) == f64)

const A0, B0: s32 = 0
#assert(A0 == B0)
#assert(A0 == 0)
#assert(#typeof(A0) == s32)
#assert(#typeof(B0) == s32)

const A2 = 1, B2 = 2
#assert(A2 == 1)
#assert(B2 == 2)
