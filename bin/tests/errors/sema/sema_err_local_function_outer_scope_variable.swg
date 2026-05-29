#global fileprivate

#test
{
    var outer = 40
    func makeCounter()->func||()->s32
    {
        return func|&outer|()->s32 { return outer } // swc-expected-error {{sema_err_local_function_outer_scope_variable}}
    }
}
