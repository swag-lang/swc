#global private

const A: #null *s32 = null
#assert(A == null)
const B: #null string = null
#assert(B == null)

#assert(A == B)     // swc-expected-error {{sema_err_compare_operand_type}}

const C: #null [..] string = null
#assert(C == null)
const D: #null any = null
#assert(D == null)

const E = "toto"
#assert(E != null)
#assert(E == "toto")
