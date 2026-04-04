#global fileprivate

func bad(a: s32)
{
    switch a { } // swc-expected-error {{parser_err_switch_missing_case}}
}
