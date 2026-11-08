#global private

var gate: Swag.Mutex

#premain
{
    gate.lock()
    Swag.print("SWAG_JIT_PREMAIN_PANIC\n")
    Swag.panic("expected premain panic", #curlocation)
}

#test { Swag.print("SWAG_JIT_TEST_AFTER_PREMAIN\n") }

#drop
{
    Swag.print("SWAG_JIT_DROP_AFTER_PREMAIN\n")
    if gate.tryLock() do
        gate.unlock()
}
