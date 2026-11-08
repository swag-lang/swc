#global private

var gate: Swag.Mutex

#test
{
    // A reported check leaves the stack intact, so the next test must still run.
    Swag.check(false, "expected check failure")
}

#test
{
    gate.lock()
    defer gate.unlock()
    Swag.print("SWAG_TEST_PANIC_STARTED\n")
    Swag.panic("expected abandoned test", #curlocation)
}

#test
{
    Swag.print("SWAG_TEST_AFTER_PANIC\n")
    gate.lock()
    gate.unlock()
}
