#global private

#test
{
    switch #complete 1
    {
    case 1:
        break
    default:     // swc-expected-error {{sema_err_switch_complete_has_default}}
        break
    }
}
