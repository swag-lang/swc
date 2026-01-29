#test
{
    switch a
    {
        break // swc-expected-error {{parser_err_switch_expected_case}}
        case a:
            break
    }
}

#test
{
    switch a { }  // swc-expected-error {{parser_err_switch_missing_case}}
}

#test
{
    switch a
    {
        case 1: // swc-expected-error {{parser_err_empty_case}}
        case 2:
            break
    }
}

#test
{
    switch a
    {
        case 1 where a > 0:
            break
        case 2:
            break
    }
}
