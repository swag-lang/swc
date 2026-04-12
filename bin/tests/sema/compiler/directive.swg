#global fileprivate

#warning("toto") // swc-expected-warning {{sema_warn_compiler_warning}}

const ENABLED  = 1
const DISABLED = 0

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
#assert(ENABLED)
#assert(!DISABLED)

#if ENABLED
{
    const MODE = 1
}
#elif DISABLED
{
    const MODE = 2
}
#else
{
    const MODE = 3
}

#assert(MODE == 1)

#if "true" // swc-expected-error {{sema_err_invalid_type}}
{
}
