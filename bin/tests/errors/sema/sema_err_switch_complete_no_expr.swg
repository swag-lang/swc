#global fileprivate

#test
{
    #[Swag.Complete]
    switch // swc-expected-error {{sema_err_switch_complete_no_expr}}
    {
        case 1:
            break
    }
}
