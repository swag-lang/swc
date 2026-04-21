#global fileprivate

alias ClosureNullary = func||()->s32

#test
{
    var value = 1
    let bad: ClosureNullary = func|value, value|()->s32 { return value } // swc-expected-error {{sema_err_closure_capture_duplicate}}
}
