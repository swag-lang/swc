#global private

// A '#scope' is not a loop, so there is nothing for 'continue' to restart.
#test
{
    #scope(Named)
    {
        continue     // swc-expected-error {{sema_err_continue_in_scope}}
    }
}

#test
{
    #scope
    {
        continue     // swc-expected-error {{sema_err_continue_in_scope}}
    }
}

// A switch inside the scope is breakable but still not a loop.
#test
{
    #scope(Named)
    {
        switch 0
        {
        case 0:
            continue     // swc-expected-error {{sema_err_continue_not_in_loop}}
        }
    }
}
