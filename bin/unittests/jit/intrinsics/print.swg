#global private

#test
{
    func printAnyFromMkAny()->s32
    {
        var x: s32 = 42
        var y: s32 = 7
        var a: any = Swag.makeAny(&x, s32)
        var b: any = Swag.makeAny(&y, s32)
        b = a
        // Swag.print("boxed", b)
        let p = cast(*s32) b.buffer
        return p[]
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
        let f           = t.flags | .Nullable
        // Swag.print("flags", f)
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
            // Swag.print("unreachable")
            return 1
        }

        // Swag.print("reachable")
        return 2
    }

    const V = #run printFoldedIf()
    #assert(V == 2)
}
