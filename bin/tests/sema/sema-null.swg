#global internal

const A: *s32 = null
#assert(A == null)
const B: string = null
#assert(B == null)

#assert(A == B) // swc-expected-error {{sema_err_compare_operand_type}}
