#test { Swag.print("SWAG_NATIVE_TEST_BEFORE_DROP\n") }

#drop { Swag.print("SWAG_NATIVE_SECOND_DROP\n") }

#drop
{
    Swag.print("SWAG_NATIVE_DROP_PANIC\n")
    Swag.panic("expected native drop panic", #curlocation)
}
