#if true
{
}
#else
{
    #error("toto")
}

#if true
{
    #error("toto") // swc-expected-error {{sema_err_compiler_error}}
    #error("toto") // swc-expected-error {{sema_err_compiler_error}}
}
#else
{
}

#if true
{
    #error("to\zto")
}
#else
{
}