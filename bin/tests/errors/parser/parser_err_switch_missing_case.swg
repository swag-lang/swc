#global fileprivate

// An empty switch body (no 'case' or 'default') is not allowed.
func bad1(a: s32)
{
    switch a {}                           // swc-expected-error {{parser_err_switch_missing_case}}
}

func bad2(a: s32)
{
    switch a
    { // swc-expected-error {{parser_err_switch_missing_case}}
    }
}
