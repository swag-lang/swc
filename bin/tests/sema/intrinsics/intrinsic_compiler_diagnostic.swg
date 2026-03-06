#global fileprivate

#run
{
    @compilererror("jit error", #curlocation) // swc1-expected-error {{sema_err_compiler_error}}
}

#run
{
    @compilerwarning("jit warning", #curlocation) // swc-expected-warning {{sema_warn_compiler_warning}}
}
