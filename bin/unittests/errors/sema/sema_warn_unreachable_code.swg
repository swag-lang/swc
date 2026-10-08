#global private

// A statement that follows a jump in the same block never runs.
func afterReturn()->s32
{
    return 1
    let dead = 2     // swc-expected-warning {{sema_warn_unreachable_code}}
    return dead
}

// One report per block: a later jump in already unreachable code says nothing new.
func twoJumps()->s32
{
    return 1
    let first = 2     // swc-expected-warning {{sema_warn_unreachable_code}}
    return first
    let second = 3
    return second
}

// A declaration silences the warning where the unreachable code is deliberate.
#[Swag.Warning("sema_warn_unreachable_code", .Disable)]
func silenced()->s32
{
    return 1
    let dead = 2
    return dead
}

// ... and promotes it where it has to stop the build.
#[Swag.Warning("sema_warn_unreachable_code", .Error)]
func promoted()->s32
{
    return 1
    let dead = 2     // swc-expected-error {{sema_warn_unreachable_code}}
    return dead
}

// "all" names every warning at once.
#[Swag.Warning("all", .Disable)]
func blanket()->s32
{
    return 1
    let dead = 2
    return dead
}

// A decision that names a warning outranks a decision that says "all".
#[Swag.Warning("all", .Disable), Swag.Warning("sema_warn_unreachable_code", .Error)]
func namedBeatsBlanket()->s32
{
    return 1
    let dead = 2     // swc-expected-error {{sema_warn_unreachable_code}}
    return dead
}

// 'Swag.panic' and 'unreachable' declare that control never gets past them. A panic hook can
// return and an 'unreachable' without its guard lowers to nothing, but either is a broken
// program, so what follows is reported like code after a 'return'.
func afterPanic()->s32
{
    Swag.panic("stop", #curlocation)
    return 2     // swc-expected-warning {{sema_warn_unreachable_code}}
}

func afterUnreachable()->s32
{
    unreachable
    return 2     // swc-expected-warning {{sema_warn_unreachable_code}}
}

#[Swag.NoReturn]
func stop()
{
    Swag.panic("stop", #curlocation)
}

// So does a call to a '#[Swag.NoReturn]' function.
func afterNoReturnCall()->s32
{
    stop()
    return 2     // swc-expected-warning {{sema_warn_unreachable_code}}
}

enum Kind
{
    First
    Second
}

// A '#complete' switch whose every case leaves the function lets nothing past it: a value
// outside the enum is the same broken program as a reached 'unreachable'.
func afterCompleteSwitch(kind: Kind)->s32
{
    switch #complete kind
    {
    case .First:  return 1
    case .Second: return 2
    }

    return 0     // swc-expected-warning {{sema_warn_unreachable_code}}
}

// A 'default' always matches, so it closes the switch the same way.
func afterDefaultSwitch(value: s32)->s32
{
    switch value
    {
    case 0:  return 1
    default: return 2
    }

    return 0     // swc-expected-warning {{sema_warn_unreachable_code}}
}

// A case that does not leave lets its value walk past the switch, and a 'break' leaves the
// switch rather than the function.
func pastSwitch(kind: Kind)->s32
{
    switch #complete kind
    {
    case .First:  return 1
    case .Second: break
    }

    return 2
}

// A jump inside a nested block ends the enclosing block too.
func nestedJump()->s32
{
    var value = 0
    while value < 10
    {
        value += 1
        {
            break
        }

        value += 1     // swc-expected-warning {{sema_warn_unreachable_code}}
    }

    return value
}

#[Swag.Macro, Swag.CalleeReturn]
func maybeRun(flag: bool, stmt: #code)
{
    if flag do
        #inject(stmt)
}

// A trailing block is the call's '#code' argument, not a statement of this block, so
// whether it runs at all is the callee's decision and nothing after it is unreachable.
func codeBlockArgument(flag: bool)->s32
{
    maybeRun(flag)
    {
        return 7
    }

    return 9
}

#test
{
    Swag.assert(afterReturn() == 1)
    Swag.assert(twoJumps() == 1)
    Swag.assert(silenced() == 1)
    Swag.assert(promoted() == 1)
    Swag.assert(blanket() == 1)
    Swag.assert(namedBeatsBlanket() == 1)
    Swag.assert(afterCompleteSwitch(.Second) == 2)
    Swag.assert(afterDefaultSwitch(3) == 2)
    Swag.assert(pastSwitch(.Second) == 2)
    Swag.assert(nestedJump() == 1)
    Swag.assert(codeBlockArgument(true) == 7)
    Swag.assert(codeBlockArgument(false) == 9)
}
