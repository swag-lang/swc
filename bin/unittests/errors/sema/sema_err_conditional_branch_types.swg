#global private

#test
{
    var flag  = true
    var count = 1's32
    let mixed = flag ? count : "text"     // swc-expected-error {{sema_err_conditional_branch_types}}
}

#test
{
    var flag  = false
    let mixed = flag ? true : "no"     // swc-expected-error {{sema_err_conditional_branch_types}}
}
