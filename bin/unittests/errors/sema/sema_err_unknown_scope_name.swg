#global private

#test
{
    #scope(Outer)
    {
        for 10
        {
            break to Outer
        }
    }
}

#test
{
    #scope(Outer)
        for 10
    {
        break to Outer
    }
}

#test
{
    #scope(A)
    {
        #scope(A)
        {
            break to A
        }

        break to A
    }
}

#test
{
    break to Missing     // swc-expected-error {{sema_err_unknown_scope_name}}
}

#test
{
    for 10
    {
        break to Missing     // swc-expected-error {{sema_err_unknown_scope_name}}
    }
}
