#global private

#warning("toto")     // swc-expected-warning {{sema_warn_compiler_warning}}

const ENABLED  = 1
const DISABLED = 0

#static if true {}
else
{
    #error("toto")
}

#static if true {}
else {}

#assert(true)
#assert(ENABLED)
#assert(!DISABLED)

#static if ENABLED
{
    const MODE = 1
}
elif DISABLED
{
    const MODE = 2
}
else
{
    const MODE = 3
}

#assert(MODE == 1)
