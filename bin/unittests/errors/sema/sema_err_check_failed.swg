#global private

// A failed check reports itself and lets the code go on: both failures are reported, and the
// function still reaches its end with every statement after them executed. Assertions being off
// changes nothing, since a check is a test verdict.
#[Swag.Safety(.Assert, false)]
func failTwoChecks()->s32
{
    var reached = 0
    Swag.check(reached == 1)     // swc-expected-error {{sema_err_check_failed}}
    reached += 1
    Swag.check(reached == 2, "second observation")     // swc-expected-error {{sema_err_check_failed}}
    reached += 1
    Swag.check(reached == 2)
    return reached
}

#test
{
    const V = #run failTwoChecks()
    #assert(V == 2)
}
