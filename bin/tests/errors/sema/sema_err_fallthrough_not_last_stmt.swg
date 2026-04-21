#global fileprivate

#test
{
    var v = 1
    switch v
    {
        case 1:
            fallthrough // swc-expected-error {{sema_err_fallthrough_not_last_stmt}}
            break
        default:
            break
    }
}

#test
{
    var v = 0
    switch v
    {
        case 0:
            fallthrough // swc-expected-error {{sema_err_fallthrough_not_last_stmt}}
            var a = 1
        case 1:
            break
    }
}
