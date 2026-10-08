#global private

// -----------------------------------------------------------------------------
// '#[Swag.NoReturn]' declares that a call never comes back. Callers rely on it, so the
// function has to keep the promise on every path.
// -----------------------------------------------------------------------------

#[Swag.NoReturn]
func stop()
{
    Swag.panic("stop", #curlocation)
}

#[Swag.NoReturn]
func reachesEnd(flag: bool)     // swc-expected-error {{sema_err_noreturn_reaches_end}}
{
    if flag do
        stop()
}

#[Swag.NoReturn]
func returnsOnOnePath(flag: bool)
{
    if flag do
        return     // swc-expected-error {{sema_err_noreturn_return}}
    stop()
}

#[Swag.NoReturn]
func declaresAResult()->s32     // swc-expected-error {{sema_err_noreturn_return_type}}
{
    stop()
}

// -----------------------------------------------------------------------------
// Valid programs: none of these must be flagged.
// -----------------------------------------------------------------------------

// A call to another 'NoReturn' function, 'unreachable', and a loop with no way out all end
// the body.
#[Swag.NoReturn]
func chained()
{
    stop()
}

#[Swag.NoReturn]
func endsWithUnreachable()
{
    unreachable
}

#[Swag.NoReturn]
func spins()
{
    for {}
}

// A function with a return type needs no 'return' after a call that never comes back.
func valueOrStop(flag: bool)->s32
{
    if flag do
        return 1
    stop()
}

// The 'return' of a closure written inside belongs to the closure.
#[Swag.NoReturn]
func closureInside()
{
    let fn = func()->s32 { return 1 }
    discard fn()
    stop()
}

#test
{
    Swag.assert(valueOrStop(true) == 1)
}
