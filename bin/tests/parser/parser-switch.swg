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
