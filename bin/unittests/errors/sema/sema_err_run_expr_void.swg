#global fileprivate

#test
{
    const V = #run @compiler.compileString("const _x = 0") // swc-expected-error {{sema_err_run_expr_void}}
}
