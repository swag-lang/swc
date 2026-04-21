#global fileprivate

// 'fallthrough' is only valid inside a switch case.
#test
{
    fallthrough                  // swc-expected-error {{sema_err_fallthrough_outside_switch_case}}
}

func bad()
{
    fallthrough                  // swc-expected-error {{sema_err_fallthrough_outside_switch_case}}
}

#test
{
    if true do fallthrough       // swc-expected-error {{sema_err_fallthrough_outside_switch_case}}
}
