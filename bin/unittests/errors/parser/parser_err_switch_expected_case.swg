#global fileprivate

// Switch bodies must start with 'case' or 'default'; stray statements are flagged.
func bad1(a: s32)
{
    switch a
    {
        break                             // swc-expected-error {{parser_err_switch_expected_case}}
        case 1:
            break
    }
}

func bad2(a: s32)
{
    switch a
    {
        var x = 1                         // swc-expected-error {{parser_err_switch_expected_case}}
        case 1:
            break
    }
}
