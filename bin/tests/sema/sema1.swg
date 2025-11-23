#warning("toto") // swc-expected-warning {{sema_warn_compiler_warning}}

#if true
{
}
#else
{
    #error("toto")
}

#if true
{
    #error("""toto""") // swc-expected-error {{sema_err_compiler_error}}
    #error(#"toto"#) // swc-expected-error {{sema_err_compiler_error}}
}
#else
{
}

#if true
{
}
#else
{
}

#assert(true)

#if "true" // swc-expected-error {{sema_err_invalid_type}}
{
}

