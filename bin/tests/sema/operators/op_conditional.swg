#global internal

#assert((true ? 10 : 20) == 10)
#assert((false ? 10 : 20) == 20)
#assert((true ? "true" : "false") == "true")
#assert((false ? "true" : "false") == "false")

#test
{
    const a = true ? 10's16 : 20's32
    #assert(#typeof(a) == s32)

    const b = false ? 10's16 : 20's32
    #assert(#typeof(b) == s32)
    #assert(b == 20)

    const c = true ? 1.0'f32 : 2.0'f64
    #assert(#typeof(c) == f64)

    const d = true ? 20's32 : 10's16
    #assert(#typeof(d) == s32)
}

#test { var a = 0 ? 1 : 2 }
#test { var b = 1.0 ? 1 : 2 }   // swc-expected-error {{sema_err_cannot_cast}}

#test { var a = true ? 10 : "string" }  // swc-expected-error {{sema_err_binary_operand_type}}
const C1 = true ? 10 : true             // swc-expected-error {{sema_err_binary_operand_type}}

#test { var a = true ? s32 : s16 }  // swc-expected-error {{sema_err_not_value_expr}}
const C2 = true ? 10 : s16          // swc-expected-error {{sema_err_not_value_expr}}

namespace NC{}
#test { var a = NC ? 10 : 20 }      // swc-expected-error {{sema_err_not_value_expr}}

#assert((true ? (false ? 1 : 2) : 3) == 2)
#assert((false ? 1 : (true ? 2 : 3)) == 2)

const VAL1 = 10
var var2 = 20
#assert((true ? VAL1 : var2) == 10)

#test
{
    var x = 10
    var y = 20
    var res = true ? x : y
    #assert(res == 10) // swc-expected-error {{sema_err_expr_not_const}}
}

#test
{
    var A: *s32
    var C = A ? A : null
}
