const A: s32    // swc-expected-error {{sema_err_const_missing_init}}
const B = @err  // swc-expected-error {{sema_err_expr_not_const}}
#print(SEMA6)   // swc-expected-error {{sema_err_unknown_identifier}}

const A = 52
const B = A
#assert(B == 52)
