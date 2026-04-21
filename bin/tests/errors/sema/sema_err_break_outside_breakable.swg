#global fileprivate

// 'break' is only valid inside a loop, scope, or switch case.
#test
{
    break                        // swc-expected-error {{sema_err_break_outside_breakable}}
}

#test
{
    if true do break             // swc-expected-error {{sema_err_break_outside_breakable}}
}

func bad()
{
    break                        // swc-expected-error {{sema_err_break_outside_breakable}}
}
