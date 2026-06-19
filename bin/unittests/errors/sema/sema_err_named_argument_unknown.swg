#global fileprivate

// A named argument that does not match any parameter name is rejected.
func Sum3(a: s32, b: s32, c: s32)->s32
{
    return a + b + c
}

#test { var r1 = Sum3(d: 1) }                    // swc-expected-error {{sema_err_named_argument_unknown}}
#test { var r2 = Sum3(a: 1, b: 2, x: 3) }        // swc-expected-error {{sema_err_named_argument_unknown}}
#test { var r3 = Sum3(zzz: 99) }                 // swc-expected-error {{sema_err_named_argument_unknown}}
