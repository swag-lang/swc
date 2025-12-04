
const A: s32    // swc-expected-error {{sema_err_const_missing_init}}
const B = @err  // swc-expected-error {{sema_err_expr_not_const}}

const A = 52
#print(A)