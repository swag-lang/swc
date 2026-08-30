#global private

func raiseCompilerError()->s32
{
    Swag.compilerError("jit error", #curlocation)     // swc-expected-error {{sema_err_compiler_error}}
    return 0
}

func raiseCompilerWarning()->s32
{
    Swag.compilerWarning("jit warning", #curlocation)     // swc-expected-warning {{sema_warn_compiler_warning}}
    return 1
}

#test
{
    const V = #run raiseCompilerError()
    Swag.assert(V == 0)
}

#test
{
    const V = #run raiseCompilerWarning()
    Swag.assert(V == 1)
}
