#global fileprivate

#test
{
    switch 1
    {
        default:
            break
        default: // swc-expected-error {{sema_err_switch_multiple_default}}
            break
    }
}
