#global private

#[Swag.Strict]
alias MksliceStrictU16Ptr      = *u16

#[Swag.Strict]
alias MksliceStrictConstS32Ptr = const *s32

#test
{
    var buf: [100] u8
    let str = Swag.makeSlice(&buf[0], buf.count)
    #assert(#typeof(str) == [..] u8)

    let str1 = Swag.makeSlice(&buf[0], 10)
    #assert(#typeof(str1) == [..] u8)
    let str2 = Swag.makeSlice(&buf[0], 10's16)
    #assert(#typeof(str2) == [..] u8)

    var backing: [20] s32
    var ptr:     const *s32 = &backing[0]
    let str3                = Swag.makeSlice(ptr, 20)
    #assert(#typeof(str3) == const [..] s32)
    Swag.assert(str.count == 100)
    Swag.assert(str1.count == 10)
    Swag.assert(str2.count == 10)
    Swag.assert(str3.count == 20)
}

#test
{
    var buf4: [100] u8
    let str4 = cast(string) Swag.makeSlice(&buf4[0], buf4.count)
    #assert(#typeof(str4) == string)
    Swag.assert(str4.count == 100)
}

#test
{
    var cstr: const cstring = cast(const cstring) ("hello").buffer
    let bytes               = Swag.makeSlice(cstr, cstr.count)
    let text                = Swag.makeString(cstr, cstr.count)

    #assert(#typeof(bytes) == const [..] u8)
    #assert(#typeof(text) == string)
    Swag.assert(bytes.count == 5)
    Swag.assert(bytes[1] == 'e'u8)
    Swag.assert(text == "hello")
}

#test
{
    var data: [6] u8  = ['h'u8, 'e'u8, 'l'u8, 'l'u8, 'o'u8, 0]
    var cstr: cstring = cast(cstring) &data[0]
    let bytes         = Swag.makeSlice(cstr, cstr.count)

    #assert(#typeof(bytes) == const [..] u8)
    Swag.assert(bytes.count == 5)
    Swag.assert(bytes[4] == 'o'u8)
}

#test
{
    var buf: [4] u8 = [10, 20, 30, 40]
    let sl          = Swag.makeSlice(&buf[2], 0)

    #assert(#typeof(sl) == [..] u8)
    Swag.assert(sl.count == 0)
}

#test
{
    var buf: [5] u8 = [1, 2, 3, 4, 5]
    let sl          = Swag.makeSlice(&buf[1], 3)

    Swag.assert(sl.count == 3)
    Swag.assert(sl[0] == 2)
    Swag.assert(sl[1] == 3)
    Swag.assert(sl[2] == 4)
}

#test
{
    var buf: [4] u16 = [11, 22, 33, 44]
    let sl           = Swag.makeSlice(&buf[0], 4)

    sl[1] = 77
    sl[3] = 99

    #assert(#typeof(sl) == [..] u16)
    Swag.assert(buf[1] == 77)
    Swag.assert(buf[3] == 99)
}

#test
{
    var buf: [3] s32    = [5, 6, 7]
    let ptr: const *s32 = &buf[0]
    let sl              = Swag.makeSlice(ptr, 3)

    #assert(#typeof(sl) == const [..] s32)
    Swag.assert(sl.count == 3)
    Swag.assert(sl[0] == 5)
    Swag.assert(sl[2] == 7)
}

#test
{
    var buf: [4] u16 = [8, 13, 21, 34]
    let ptr          = cast(MksliceStrictU16Ptr) &buf[0]
    let sl           = Swag.makeSlice(ptr, 3)

    #assert(#typeof(sl) == [..] u16)
    Swag.assert(sl.count == 3)
    Swag.assert(sl[0] == 8)
    Swag.assert(sl[2] == 21)
}

#test
{
    var buf: [3] s32 = [5, 10, 15]
    let ptr          = cast(MksliceStrictConstS32Ptr) &buf[0]
    let sl           = Swag.makeSlice(ptr, 2)

    #assert(#typeof(sl) == const [..] s32)
    Swag.assert(sl.count == 2)
    Swag.assert(sl[0] == 5)
    Swag.assert(sl[1] == 10)
}
