#global fileprivate

alias ClosureNullary = func||()->s32

#test
{
    let fixed = 10
    let bad: ClosureNullary = func|&fixed|()->s32 { return fixed } // swc-expected-error {{sema_err_closure_capture_let_by_ref}}
}
