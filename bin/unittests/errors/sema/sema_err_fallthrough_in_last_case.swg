#global fileprivate

#test
{
    var v = 1
    switch v
    {
        case 1:
            break
        default:
            fallthrough // swc-expected-error {{sema_err_fallthrough_in_last_case}}
    }
}
