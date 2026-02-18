#global internal

#if #os == Swag.TargetOs.Windows
{
    const A = #os == Swag.TargetOs.Windows
    #assert(A)
    const B = true
}

#if #os == Swag.TargetOs.Linux
{
    const A = #os == Swag.TargetOs.Linux
    #assert(A)
    const B = true
}

#if #os == Swag.TargetOs.MaxOSX
{
    const A = #os == Swag.TargetOs.MaxOSX
    #assert(A)
    const B = true
}

#test
{
    const A = #arch
    #assert(#typeof(A) == Swag.TargetArch)
}

#test
{
    const C = #cpu
    #assert(#typeof(C) == string)
    #assert(C != "")
}

#test
{
    const C = #cfg
    #assert(#typeof(C) == string)
    #assert(C != "")
}

#test
{
    const O = #swagos
    #assert(#typeof(O) == Swag.TargetOs)
}

#test
{
    const A = #arch
    #assert(#typeof(A) == string) // swc-expected-error {{sema_err_compiler_assert}}
}

#test
{
    const C = #cpu
    #assert(#typeof(C) == Swag.TargetArch) // swc-expected-error {{sema_err_compiler_assert}}
}

#test
{
    const C = #cfg
    #assert(#typeof(C) == Swag.TargetOs) // swc-expected-error {{sema_err_compiler_assert}}
}

#test
{
    const O = #swagos
    #assert(#typeof(O) == string) // swc-expected-error {{sema_err_compiler_assert}}
}
