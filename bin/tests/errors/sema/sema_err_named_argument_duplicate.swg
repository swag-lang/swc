#global fileprivate

// A named argument cannot be specified more than once in the same call.
func Sum3(a: s32, b: s32, c: s32)->s32
{
    return a + b + c
}

#test { var r1 = Sum3(a: 1, a: 2, b: 3) }        // swc-expected-error {{sema_err_named_argument_duplicate}}
#test { var r2 = Sum3(b: 10, b: 20, c: 5) }      // swc-expected-error {{sema_err_named_argument_duplicate}}
#test { var r3 = Sum3(c: 7, b: 5, c: 9) }        // swc-expected-error {{sema_err_named_argument_duplicate}}
