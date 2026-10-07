#global private

// Inlining into a test must preserve the callee's 'try', even though a 'try'
// written directly in the test is an 'expect'. Both handler orders exercise this.
struct InlineError
{
    using base: Swag.BaseError
    code:       s32
}

#[Swag.NoInline]
func raiseError() fail
{
    fail InlineError{base: Swag.BaseError{"inline failure"}, code: 7}
}

#[Swag.NoInline]
func succeeds(ok: bool)->bool => ok

#[Swag.Inline]
func checkedVoid(ok: bool) fail
{
    if not succeeds(ok) do
        try raiseError()
}

#[Swag.Inline]
func checkedValue(ok: bool)->s32 fail
{
    if not succeeds(ok) do
        try raiseError()
    return 42
}

#test
{
    catch checkedVoid(false) as err
    Swag.assert((err is InlineError))
    Swag.assert((cast #assume(InlineError) err).code == 7)
    expect checkedVoid(true)
}

#test
{
    expect checkedVoid(true)
    catch checkedVoid(false) as err
    Swag.assert((err is InlineError))
}

#test
{
    let value = expect checkedValue(true)
    Swag.assert(value == 42)
    discard catch checkedValue(false) as err
    Swag.assert((err is InlineError))
}

#test
{
    discard catch checkedValue(false) as err
    Swag.assert((err is InlineError))
    let value = expect checkedValue(true)
    Swag.assert(value == 42)
}

#[Swag.Macro]
func raiseFromMacro() fail
{
    try raiseError()
}

#[Swag.Macro]
func injectStatement(stmt: #code)
{
    #inject(stmt)
}

#[Swag.Inline]
func checkedMacro() fail
{
    try raiseFromMacro()
}

#[Swag.Inline]
func checkedInjection() fail
{
    injectStatement(#code { try raiseError() })
}

#test
{
    catch checkedMacro() as err
    Swag.assert((err is InlineError))
}

#test
{
    catch checkedInjection() as err
    Swag.assert((err is InlineError))
}

#[Swag.Inline]
func identity(value: s32)->s32 => value

// Successful test-owned 'try' calls also work with safety guards disabled.
// Terminal failures through substitution and injection run in subprocess tests.
#[Swag.Safety(.Expect, false)]
#test
{
    var reached = false
    defer Swag.assert(reached)
    let value = identity(try checkedValue(true))
    Swag.assert(value == 42)
    reached = true
}

#[Swag.Safety(.Expect, false)]
#test
{
    var reached = false
    defer Swag.assert(reached)
    injectStatement(#code { try checkedVoid(true) })
    reached = true
}
