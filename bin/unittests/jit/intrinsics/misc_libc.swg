#global private

#test
{
    #[Swag.NoInline]
    func allocWriteRead()->bool
    {
        let ptr = cast([*] u8?, testAlloc(4))
        if not ptr
        {
            return false
        }

        ptr[0] = 10_u8
        ptr[1] = 20_u8
        ptr[2] = 30_u8
        ptr[3] = 40_u8

        let ok = ptr[0] == 10_u8 and ptr[1] == 20_u8 and ptr[2] == 30_u8 and ptr[3] == 40_u8
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
        var ptr = cast([*] u8?, testAlloc(4))
        if not ptr
        {
            return false
        }

        ptr[0] = 1_u8
        ptr[1] = 2_u8
        ptr[2] = 3_u8
        ptr[3] = 4_u8

        ptr = cast([*] u8?, testRealloc(ptr, 8))
        if not ptr
        {
            return false
        }

        let ok = ptr[0] == 1_u8 and ptr[1] == 2_u8 and ptr[2] == 3_u8 and ptr[3] == 4_u8
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
        let s = cast(const cstring, ("hello").buffer)
        return s.count
    }

    #assert(#run cstringCountBasic() == 5)
}
