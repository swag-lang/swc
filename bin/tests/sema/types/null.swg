#global fileprivate

const A: *s32 = null
#assert(A == null)
const B: string = null
#assert(B == null)

const C: [..] string = null
#assert(C == null)
const D: any = null
#assert(D == null)

const E = "toto"
#assert(E != null)
#assert(E == "toto")
