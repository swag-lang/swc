#global fileprivate

// A case or default section must contain at least one statement (or 'fallthrough').
func bad1(a: s32)
{
    switch a
    {
        case 1: // swc-expected-error {{parser_err_empty_case}}
    }
}

func bad2(a: s32)
{
    switch a
    {
        default: // swc-expected-error {{parser_err_empty_case}}
    }
}

func bad3(a: s32)
{
    switch a
    {
        case 1: // swc-expected-error {{parser_err_empty_case}}
        case 2:
            break
    }
}
