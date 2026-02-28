#global fileprivate

#test
{
    func mkanyRoundtripS32()->s32
    {
        var x: s32 = 42
        let a: any = @mkany(&x, s32)
        let p = cast(*s32) @dataof(a)
        return dref p
    }

    const V = #run mkanyRoundtripS32()
    #assert(V == 42)
}

#test
{
    func mkanyAssignAny()->s32
    {
        var x: s32 = 123
        var y: s32 = 7
        var a: any = @mkany(&x, s32)
        var b: any = @mkany(&y, s32)
        b = a
        let p = cast(*s32) @dataof(b)
        return dref p
    }

    const V = #run mkanyAssignAny()
    #assert(V == 123)
}

#test
{
    func mkanyKindof()->bool
    {
        var x: s64 = 9000
        let a: any = @mkany(&x, s64)
        return @kindof(a) == s64
    }

    const V = #run mkanyKindof()
    #assert(V)
}
