#global fileprivate

#test
{
    func printAnyFromMkAny()->s32
    {
        var x: s32 = 42
        var y: s32 = 7
        var a: any = @mkany(&x, s32)
        var b: any = @mkany(&y, s32)
        b = a
        @print("boxed", b)
        let p = cast(*s32) @dataof(b)
        return dref p
    }

    const V = #run printAnyFromMkAny()
    #assert(V == 42)
}

#test
{
    #[Swag.Optimize(false)]
    func printTypeInfoFlags()->bool
    {
        let t: typeinfo = #typeof(s32)
        let f = t.flags | .Nullable
        @print("flags", f)
        return (f & .Nullable) != 0
    }

    const V = #run printTypeInfoFlags()
    #assert(V)
}

#test
{
    #[Swag.Optimize(true)]
    func printFoldedIf()->s32
    {
        if false
        {
            @print("unreachable")
            return 1
        }

        @print("reachable")
        return 2
    }

    const V = #run printFoldedIf()
    #assert(V == 2)
}
