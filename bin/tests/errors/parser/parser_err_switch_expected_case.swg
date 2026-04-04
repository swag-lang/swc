#global fileprivate

func bad(a: s32)
{
    switch a
    {
        break // swc-expected-error {{parser_err_switch_expected_case}}
        case a:
            break
    }
}
