#global internal

var A: s32 = true                 // swc-expected-error {{sema_err_cannot_cast}}
var B: s32
var C: f32 = 1
#assert(#typeof(C) == f32)
var D = 1.0
#assert(#typeof(D) == f32)

var E = D // swc-expected-error {{sema_err_expr_not_const}}

struct F
{
    A = D // swc-expected-error {{sema_err_expr_not_const}}
}

#test
{
    var D0 = 1.0
    var E0 = D0

    let L0: s32 // swc-expected-error {{sema_err_let_missing_init}}
    let L1 = 10
}

#test
{
    var x = true
    #assert(#typeof(x) == bool)

    var y: u16 = 5
    var z = y
    #assert(#typeof(z) == u16)
}

#test
{
    let a = 1
    a = 2 // swc-expected-error {{sema_err_assign_to_let}}
}
