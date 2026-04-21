#global fileprivate

alias ClosureNullary = func||()->s32

func addOne(value: s32)->s32 => value + 1

#test
{
    let bad: ClosureNullary = func|addOne|()->s32 { return 0 } // swc-expected-error {{sema_err_closure_capture_invalid}}
}
