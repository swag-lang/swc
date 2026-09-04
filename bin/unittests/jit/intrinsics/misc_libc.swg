#global private

#test
{
    #[Swag.NoInline]
    func allocWriteRead()->bool
    {
        let ptr = cast([*] u8?) testAlloc(4)
        if !ptr do
            return false

        ptr[0] = 10'u8
        ptr[1] = 20'u8
        ptr[2] = 30'u8
        ptr[3] = 40'u8

        let ok = ptr[0] == 10'u8 and ptr[1] == 20'u8 and ptr[2] == 30'u8 and ptr[3] == 40'u8
        testFree(ptr)
        return ok
    }

    #assert(#run allocWriteRead())
}

#test
{
    #[Swag.NoInline]
    func reallocGrow()->bool
    {
        var ptr = cast([*] u8?) testAlloc(4)
        if !ptr do
            return false

        ptr[0] = 1'u8
        ptr[1] = 2'u8
        ptr[2] = 3'u8
        ptr[3] = 4'u8

        ptr = cast([*] u8?) testRealloc(ptr, 8)
        if !ptr do
            return false

        let ok = ptr[0] == 1'u8 and ptr[1] == 2'u8 and ptr[2] == 3'u8 and ptr[3] == 4'u8
        testFree(ptr)
        return ok
    }

    #assert(#run reallocGrow())
}

#test
{
    #[Swag.NoInline]
    func cstringCountBasic()->u64
    {
        let s = cast(const cstring) ("hello").buffer
        return s.count
    }

    #assert(#run cstringCountBasic() == 5)
}
