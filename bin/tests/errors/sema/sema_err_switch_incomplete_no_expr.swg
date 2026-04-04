#global fileprivate

#test
{
    #[Swag.Incomplete]
    switch // swc-expected-error {{sema_err_switch_incomplete_no_expr}}
    {
        case 1:
            break
    }
}
