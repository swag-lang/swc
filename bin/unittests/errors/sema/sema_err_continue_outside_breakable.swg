#global fileprivate

// 'continue' is only valid inside a loop or scope.
#test
{
    continue                     // swc-expected-error {{sema_err_continue_outside_breakable}}
}

func bad()
{
    continue                     // swc-expected-error {{sema_err_continue_outside_breakable}}
}

#test
{
    if true do continue          // swc-expected-error {{sema_err_continue_outside_breakable}}
}
