#global private

func condition(count: *s32)->bool
{
    count[] += 1
    return true
}

func message(count: *s32)->string
{
    count[] += 10
    return "verdict message"
}

// A verdict evaluates its condition whatever the assertion setting, and its message only when it
// fails.
#[Swag.NoInline, Swag.Safety(.Assert, false)]
func passingVerdicts()->s32
{
    var count = 0
    Swag.require(condition(&count), message(&count))
    Swag.check(condition(&count), message(&count))
    return count
}

#[Swag.Safety(.Assert, false)]
func requireNarrows(value: *s32?)->s32
{
    Swag.require(value != null)
    return value[]
}

#test
{
    const Passing = #run passingVerdicts()
    #assert(Passing == 2)
    Swag.require(passingVerdicts() == 2)
    var value = 42
    Swag.require(requireNarrows(&value) == 42)
}

// A failed check marks the running test and lets it go on. The JIT reports a failed check as an
// error of the compilation, so only the native runner takes this path; the test then clears the
// mark it has just proved.
#test
{
    if Swag.jit() do
        return

    var reached = 0
    Swag.check(reached == 1, "expected failure: the test goes on after it")
    reached += 1
    Swag.require(reached == 1 and Swag.g_TestFailed)
    Swag.g_TestFailed = false
}
