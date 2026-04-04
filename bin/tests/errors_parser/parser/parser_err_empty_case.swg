#global fileprivate

func bad(a: s32)
{
    switch a
    {
        case 1: // swc-expected-error {{parser_err_empty_case}}
    }
}
