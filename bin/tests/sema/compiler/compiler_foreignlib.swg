#global internal

#foreignlib("user32")
#foreignlib("user32")

#if false
{
    #foreignlib("ignored")
}

#foreignlib(1) // swc-expected-error {{sema_err_invalid_type}}
