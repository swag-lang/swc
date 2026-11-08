#global private

var gate: Swag.Mutex

#init
{
    gate.lock()
    Swag.print("SWAG_JIT_INIT_PANIC\n")
    Swag.panic("expected init panic", #curlocation)
}

#test { Swag.print("SWAG_JIT_TEST_AFTER_INIT\n") }

#drop
{
    Swag.print("SWAG_JIT_DROP_AFTER_INIT\n")
    if gate.tryLock() do
        gate.unlock()
}
