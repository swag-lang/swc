#global internal

const A = 52
const B = A
#assert(B == 52)

internal
{
    const C = A + 10
    #assert(C == 62)
}

internal const D = A * 2
#assert(D == 104)

// swc-expected-error@(+1,+2) {{sema_err_already_defined}}
const G = 52
const G = 520

const AA: s32    // swc-expected-error {{sema_err_const_missing_init}}
const BB = @err  // swc-expected-error {{sema_err_expr_not_const}}
#print(SEMA6)   // swc-expected-error {{sema_err_unknown_symbol}}

const V0 = 1
#assert(#typeof(V0) == s32)
const V1 = 1.0
#assert(#typeof(V1) == f32)
const V2 = 0x1FFFFFFFF
#assert(#typeof(V2) == u64)
const V3 = 10000000000000000000.0
#assert(#typeof(V3) == f64)
