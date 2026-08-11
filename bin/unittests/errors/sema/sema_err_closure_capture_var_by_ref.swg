#global private

alias ClosureNullary = func||()->s32

// '&' already captures the source variable itself, so it is writable without 'var'.
#test
{
    var counter             = 0
    let bad: ClosureNullary = func|var &counter|()->s32 { return counter }     // swc-expected-error {{sema_err_closure_capture_var_by_ref}}
}

#test
{
    var counter             = 0
    let bad: ClosureNullary = func|var &current = counter|()->s32 { return current }     // swc-expected-error {{sema_err_closure_capture_var_by_ref}}
}
