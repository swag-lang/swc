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
}
#else
{
}