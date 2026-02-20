#global internal

#test
{
    var p: [*]s32 = null

    var off1: u8 = 1

    let a = p + 1
    #assert(#typeof(a) == [*]s32)

    let a2 = p + off1
    #assert(#typeof(a2) == [*]s32)

    let b = 1 + p
    #assert(#typeof(b) == [*]s32)

    let b2 = off1 + p
    #assert(#typeof(b2) == [*]s32)

    let c = p - 1
    #assert(#typeof(c) == [*]s32)

    let c2 = p - off1
    #assert(#typeof(c2) == [*]s32)
}

#test
{
    var p1: [*]s32 = null
    var p2: [*]s32 = null

    let d = p1 - p2
    #assert(#typeof(d) == s64)

    let p3 = p1 + p2 // swc-expected-error {{sema_err_binary_operand_type}}
}

#test
{
    var p: *s32 = null
    let a = p + 1 // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}

#test
{
    var p: [*] void = null
    let a = p + 1 // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}

#test
{
    var p: *s32 = null
    var b: [*]s32 = null
    let a = p - b // swc-expected-error {{sema_err_pointer_arithmetic_value_ptr}}
}
