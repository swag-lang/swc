#global fileprivate

func Sum3(a: s32, b: s32, c: s32)->s32
{
    return a + b + c
}

#test { var R = Sum3(d: 1) } // swc-expected-error {{sema_err_named_argument_unknown}}
