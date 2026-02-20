#global internal

#test
{
    var a: *s32
    var b: *s8
    let c = a == b
    let d = a <= b
}

#test
{
    var a: *s32 = null
    let b = a == null
    let c = a != null
    #assert(#typeof(b) == bool)
    #assert(#typeof(c) == bool)
}

#test
{
    var a: *s32
    var b: *s8
    let c = a < b
    let d = a > b
    let e = a >= b
}

#test
{
    var a: *s32
    let b = a == 1 // swc-expected-error {{sema_err_compare_operand_type}}
}

#test
{
    var a: *s32
    let b = a < true // swc-expected-error {{sema_err_compare_operand_type}}
}
