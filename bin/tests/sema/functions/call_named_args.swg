#global internal

func Sum3(a: s32, b: s32, c: s32)->s32
{
    return a + b + c
}

func Sum3Default(a: s32, b: s32 = 5, c: s32 = 6)->s32
{
    return a + b + c
}

#test
{
    var R = Sum3(a: 1, c: 3, b: 2)
    @assert(R == 6)
}

#test
{
    var R = Sum3(1, c: 3, b: 2)
    @assert(R == 6)
}

#test
{
    var R = Sum3Default(c: 3, a: 1)
    @assert(R == 9)
}

#test { var R = Sum3(b: 2, 1) } // swc-expected-error {{sema_err_unnamed_parameter}}
#test { var R = Sum3(d: 1) } // swc-expected-error {{sema_err_named_argument_unknown}}
#test { var R = Sum3(a: 1, a: 2, b: 3) } // swc-expected-error {{sema_err_named_argument_duplicate}}
#test { var R = Sum3(b: 2) } // swc-expected-error {{sema_err_too_few_arguments}}
