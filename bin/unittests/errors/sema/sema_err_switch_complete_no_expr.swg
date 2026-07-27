#global private

#test
{
    switch #complete     // swc-expected-error {{sema_err_switch_complete_no_expr}}
    {
    case 1:
        break
    }
}
