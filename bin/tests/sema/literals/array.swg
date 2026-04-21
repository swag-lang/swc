#global fileprivate

const A: [5] s32 = [1's32, 2, 3, 4, 5]
#assert(#typeof(A) == #type [5] s32)

const A1: [5] s32 = [1, 2, 3, 4, 5]
#assert(#typeof(A1) == #type [5] s32)

const Af: [2] f64 = [1.0'f64, 2.0]
#assert(#typeof(Af) == #type [2] f64)

const A2 = [1, true, 3]
#assert(A2[0] == 1)
#assert(A2[1] == true)
#assert(A2[2] == 3)

#test
{
    var x = 1
    var B: [3] s32 = [x, 2, 3]
    #assert(#typeof(B) == #type [3] s32)

    var C: [3] s32 = [x, 2, 3]
    #assert(#typeof(C) == #type [3] s32)

    var D: [2] f32 = [1.0'f32, cast(f32) 2]
    #assert(#typeof(D) == #type [2] f32)
    #assert(#typeof(D[0]) == f32)
    #assert(#typeof(D[1]) == f32)
}

const G: [2] f32 = [1.0, 2]
#assert(#typeof(G) == #type [2] f32)
#assert(#typeof(G[0]) == f32)
#assert(#typeof(G[1]) == f32)
#assert(G[0] == 1.0)
#assert(G[1] == 2.0)

const G1: [3] [1] f32 = [[1.0], [2.0], [3.0]]
#assert(#typeof(G1) == #type [3] [1] f32)
#assert(#typeof(G1[0]) == #type [1] f32)
#assert(#typeof(G1[0][0]) == f32)
#assert(G1[2][0] == 3.0)

const I: [2] s32 = [1, cast(s32) 2.2]
#assert(#typeof(I) == #type [2] s32)
#assert(#typeof(I[0]) == s32)
#assert(#typeof(I[1]) == s32)
#assert(I[1] == 2)

#test
{
    const M: [2] [2] s32 = [[1, 2], [3, 4]]
    #assert(#typeof(M) == #type [2] [2] s32)
    #assert(M[1][0] == 3)
}

const AB: [2] u32 = [1, 2]
const AB1: [?] u32 = [1, 2]
#assert(#typeof(AB1) == #type [2] u32)

const AB2: [?] u32 = [[1], [2]]
#assert(#typeof(AB2) == #type [2] [1] u32)

// Aggregate array literal concretization (compile-time type checks only).
const SemaLitArr0 = [10, 20, 30]
#assert(#typeof(SemaLitArr0) == #type [3] s32)

const SemaLitArr1 = [1'f64, 2, 3]
#assert(#typeof(SemaLitArr1) == #type [3] f64)

const SemaLitArr2 = [[1, 2], [3, 4]]
#assert(#typeof(SemaLitArr2) == #type [2][2] s32)
#assert(@countof(SemaLitArr2) == 2)

const SemaLitArr3 = [0'u16, 31, 59]
#assert(#typeof(SemaLitArr3) == #type [3] u16)
#assert(SemaLitArr3[1] == 31'u16)
#assert(SemaLitArr3[2] == 59'u16)

const SemaLitArr4 = [[0'u16, 31], [59, 90]]
#assert(#typeof(SemaLitArr4) == #type [2][2] u16)
#assert(SemaLitArr4[0][1] == 31'u16)
#assert(SemaLitArr4[1][1] == 90'u16)

fileprivate
{
    const HexFill = 0xF0
}

const SemaLitArr5: [2] u8 = [HexFill, HexFill]
#assert(#typeof(SemaLitArr5) == #type [2] u8)
#assert(SemaLitArr5[0] == 0xF0'u8)
#assert(SemaLitArr5[1] == 0xF0'u8)

const SemaLitArr6: [3] u8 = HexFill
#assert(#typeof(SemaLitArr6) == #type [3] u8)
#assert(SemaLitArr6[0] == 0xF0'u8)
#assert(SemaLitArr6[2] == 0xF0'u8)
