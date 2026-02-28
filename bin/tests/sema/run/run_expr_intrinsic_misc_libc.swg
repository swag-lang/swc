#global fileprivate

#test
{
    #[Swag.NoInline]
    func allocWriteRead()->bool
    {
        let ptr = cast([*] u8) @alloc(4)
        if !ptr do
            return false

        ptr[0] = 10'u8
        ptr[1] = 20'u8
        ptr[2] = 30'u8
        ptr[3] = 40'u8

        let ok = ptr[0] == 10'u8 and ptr[1] == 20'u8 and ptr[2] == 30'u8 and ptr[3] == 40'u8
        @free(ptr)
        return ok
    }

    #assert(#run allocWriteRead())
}

#test
{
    #[Swag.NoInline]
    func reallocGrow()->bool
    {
        var ptr = cast([*] u8) @alloc(4)
        if !ptr do
            return false

        ptr[0] = 1'u8
        ptr[1] = 2'u8
        ptr[2] = 3'u8
        ptr[3] = 4'u8

        ptr = cast([*] u8) @realloc(ptr, 8)
        if !ptr do
            return false

        let ok = ptr[0] == 1'u8 and ptr[1] == 2'u8 and ptr[2] == 3'u8 and ptr[3] == 4'u8
        @free(ptr)
        return ok
    }

    #assert(#run reallocGrow())
}

#test
{
    #[Swag.NoInline]
    func strlenBasic()->u64
    {
        let s = cast(cstring) @dataof("hello")
        return @strlen(s)
    }

    #assert(#run strlenBasic() == 5)
}
