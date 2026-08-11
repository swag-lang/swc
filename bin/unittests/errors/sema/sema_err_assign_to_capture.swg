#global private

alias ClosureNullary = func||()->s32

// A by-value capture is read-only unless the capture list says 'var'.
#test
{
    var counter             = 0
    let bad: ClosureNullary = func|counter|()->s32
    {
        counter += 1     // swc-expected-error {{sema_err_assign_to_capture}}
        return counter
    }
}

// The alias form follows the same rule.
#test
{
    let start               = 10
    let bad: ClosureNullary = func|value = start|()->s32
    {
        value = 0     // swc-expected-error {{sema_err_assign_to_capture}}
        return value
    }
}
