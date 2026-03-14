#global fileprivate

#test
{
    func mkSliceCount()->u64
    {
        var buf: [6] u8 = [65, 66, 67, 68, 69, 70]
        let sl = @mkslice(&buf[0], 6)
        return @countof(sl)
    }

    const V = #run mkSliceCount()
    #assert(V == 6)
}

#test
{
    func mkSliceRead()->u8
    {
        var buf: [4] u8 = [10, 20, 30, 40]
        let sl = @mkslice(&buf[1], 3)
        return sl[1]
    }

    const V = #run mkSliceRead()
    #assert(V == 30'u8)
}

#test
{
    func mkStringCount()->u64
    {
        var buf: [5] u8 = [72, 101, 108, 108, 111]
        let s = @mkstring(&buf[0], 5)
        return @countof(s)
    }

    const V = #run mkStringCount()
    #assert(V == 5)
}

#test
{
    func mkStringRead()->u8
    {
        var buf: [3] u8 = [120, 121, 122]
        let s = @mkstring(&buf[0], 3)
        return s[2]
    }

    const V = #run mkStringRead()
    #assert(V == 122'u8)
}

#test
{
    var s = @mkstring(0, 1) // swc-expected-error {{sema_err_expected_type_fam}}
}

#test
{
    var buf: [2] u8
    var s = @mkslice(&buf[0], 0.0) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    func mkSliceWriteThrough()->bool
    {
        var buf: [4] u8 = [1, 2, 3, 4]
        let sl = @mkslice(&buf[0], 4)
        sl[2] = 9
        return @countof(sl) == 4 and buf[2] == 9'u8 and sl[2] == 9'u8
    }

    const V = #run mkSliceWriteThrough()
    #assert(V)
}

#test
{
    func mkStringToByteView()->bool
    {
        var buf: [5] u8 = [72, 101, 108, 108, 111]
        let text = @mkstring(&buf[0], 5)
        let bytes = cast(const [..] u8) text
        return text == "Hello" and @countof(bytes) == 5 and bytes[0] == 72'u8 and bytes[4] == 111'u8
    }

    const V = #run mkStringToByteView()
    #assert(V)
}
