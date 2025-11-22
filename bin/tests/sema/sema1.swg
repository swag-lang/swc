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
    #error("to\zto") // swc-expected-error {{lex_err_invalid_escape}}
}
#else
{
}