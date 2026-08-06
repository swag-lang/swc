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

// '@panic' and 'unreachable' announce that control never reaches them, but neither is
// guaranteed to leave the block — a panic hook returns to the caller, and 'unreachable'
// lowers to nothing with its guard off — so nothing after them is reported.
func notGuaranteed()->s32
{
    @panic("stop", #curlocation)
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
    @assert(afterReturn() == 1)
    @assert(twoJumps() == 1)
    @assert(silenced() == 1)
    @assert(promoted() == 1)
    @assert(blanket() == 1)
    @assert(namedBeatsBlanket() == 1)
    @assert(nestedJump() == 1)
    @assert(codeBlockArgument(true) == 7)
    @assert(codeBlockArgument(false) == 9)
}
