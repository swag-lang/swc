#global private

#test
{
    switch 0
    {
        case 0:
            continue // swc-expected-error {{sema_err_continue_not_in_loop}}
    }
}
