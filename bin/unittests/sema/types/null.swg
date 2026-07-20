#global private

const A: #null *s32 = null
#assert(A == null)
const B: #null string = null
#assert(B == null)

const C: #null [..] #null string = null
#assert(C == null)
const D: #null any = null
#assert(D == null)

const E = "toto"
#assert(E != null)
#assert(E == "toto")
