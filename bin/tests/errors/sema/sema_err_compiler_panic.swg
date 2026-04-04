#global fileprivate

func raiseCompilerPanic()->s32
{
    @panic("jit panic", #curlocation) // swc-expected-error {{sema_err_compiler_panic}}
    return 0
}

#test
{
    const v = #run raiseCompilerPanic()
    @assert(v == 0)
}
