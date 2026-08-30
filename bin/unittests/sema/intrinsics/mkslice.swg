#global private

func semaTest001()
{
    var buf: [100] u8
    let str = Swag.makeSlice(&buf[0], buf.count)
    #assert(#typeof(str) == [..] u8)

    let str1 = Swag.makeSlice(&buf[0], 10)
    #assert(#typeof(str1) == [..] u8)
    let str2 = Swag.makeSlice(&buf[0], 10's16)
    #assert(#typeof(str2) == [..] u8)

    var xv:  s32
    var ptr: const *s32 = &xv
    let str3            = Swag.makeSlice(ptr, 20)
    #assert(#typeof(str3) == const [..] s32)
}

func semaTest002()
{
    var buf4: [100] u8
    let str4 = cast(string) Swag.makeSlice(&buf4[0], buf4.count)
    #assert(#typeof(str4) == string)
}
