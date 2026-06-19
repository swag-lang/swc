#global fileprivate

alias ClosureUnary = func||(s32)->s32
alias ClosureNullary = func||()->s32

#test
{
    let outer = 5
    let bad: ClosureUnary = func(value: s32)->s32 { return outer + value } // swc-expected-error {{sema_err_closure_capture_missing}}
}

#test
{
    let outer = 7
    let bad: ClosureNullary = func|outer|()->s32
    {
        let inner = func()->s32 { return outer } // swc-expected-error {{sema_err_closure_capture_missing}}
        return inner()
    }
}
