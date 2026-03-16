#global fileprivate // swc-option suite-jit

func raiseCompilerError()->s32
{
    @compilererror("jit error", #curlocation) // swc-expected-error {{sema_err_compiler_error}}
    return 0
}

func raiseCompilerWarning()->s32
{
    @compilerwarning("jit warning", #curlocation) // swc-expected-warning {{sema_warn_compiler_warning}}
    return 1
}

#test
{
    const V = #run raiseCompilerError()
    @assert(V == 0)
}

#test
{
    const V = #run raiseCompilerWarning()
    @assert(V == 1)
}
