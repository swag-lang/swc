#global private

func raiseCompilerPanic()->s32
{
    Swag.panic("jit panic", #curlocation)     // swc-expected-error {{sema_err_compiler_panic}}
    return 0
}

#test
{
    const v = #run raiseCompilerPanic()
    Swag.assert(v == 0)
}
