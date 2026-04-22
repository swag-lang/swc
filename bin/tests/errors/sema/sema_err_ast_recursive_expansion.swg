#global fileprivate

#[Swag.Compiler]
func recursiveAst()->string
{
    return "#ast recursiveAst() // swc-expected-error {{sema_err_ast_recursive_expansion}}"
}

#ast recursiveAst()
