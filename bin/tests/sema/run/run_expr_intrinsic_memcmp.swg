#global fileprivate

#test
{
    func memCmpEq()->bool
    {
        var a: [4] u8 = [1, 2, 3, 4]
        var b: [4] u8 = [1, 2, 3, 4]
        return @memcmp(&a[0], &b[0], 4) == 0
    }

    const V = #run memCmpEq()
    #assert(V)
}

#test
{
    func memCmpLess()->bool
    {
        var a: [4] u8 = [1, 2, 3, 4]
        var b: [4] u8 = [1, 2, 9, 4]
        return @memcmp(&a[0], &b[0], 4) < 0
    }

    const V = #run memCmpLess()
    #assert(V)
}

#test
{
    func memCmpGreater()->bool
    {
        var a: [4] u8 = [9, 2, 3, 4]
        var b: [4] u8 = [1, 2, 3, 4]
        return @memcmp(&a[0], &b[0], 4) > 0
    }

    const V = #run memCmpGreater()
    #assert(V)
}

#test
{
    func memCmpZeroSize()->s32
    {
        var a: [2] u8 = [1, 2]
        var b: [2] u8 = [9, 8]
        return @memcmp(&a[0], &b[0], 0)
    }

    const V = #run memCmpZeroSize()
    #assert(V == 0)
}

#test
{
    func memCmpPrefix()->s32
    {
        var a: [4] u8 = [1, 2, 3, 9]
        var b: [4] u8 = [1, 2, 3, 4]
        return @memcmp(&a[0], &b[0], 3)
    }

    const V = #run memCmpPrefix()
    #assert(V == 0)
}

#test
{
    func memCmpStringEq()->bool
    {
        let a = "hello"
        let b = "hello"
        return @memcmp(@dataof(a), @dataof(b), @countof(a)) == 0
    }

    const V = #run memCmpStringEq()
    #assert(V)
}
