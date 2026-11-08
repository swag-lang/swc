#test { Swag.print("SWAG_JIT_TEST_BEFORE_DROP\n") }

#drop { Swag.print("SWAG_JIT_SECOND_DROP\n") }

#drop
{
    Swag.print("SWAG_JIT_DROP_PANIC\n")
    Swag.panic("expected drop panic", #curlocation)
}
