#global private

// A bare 'break' never leaves a '#scope', named or not.
#test
{
    #scope(Named)
    {
        break     // swc-expected-error {{sema_err_break_targets_scope}}
    }
}

#test
{
    #scope
    {
        break     // swc-expected-error {{sema_err_break_targets_scope}}
    }
}

// The scope hides no enclosing loop either: the loop ended before the scope started.
#test
{
    for 10
    {
    }

    #scope(Named)
    {
        break     // swc-expected-error {{sema_err_break_targets_scope}}
    }
}
