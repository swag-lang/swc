#global private

func semaTest001()
{
    var ax: s32
    var x: *s32 = &ax
    var b = cast([*]s32) x

    var v: *s32 = b
    #assert(#typeof(v) == *s32)

    var v2 = cast(*s32) b
    #assert(#typeof(v2) == *s32)
}

func semaTest002()
{
    var ax: s32
    var x: *s32 = &ax
    var b = cast([*]s32) x

    var v: *s32 = b
    #assert(#typeof(v) == *s32)

    var v2 = cast(*s32) b
    #assert(#typeof(v2) == *s32)

    var b3 = cast([*]s32) x
    #assert(#typeof(b3) == [*]s32)
}

func semaTest003()
{
    var ax: s32
    var x: *s32 = &ax
    var y = cast(*u8) x
    #assert(#typeof(y) == *u8)
}

func semaTest004()
{
    var ax: s32
    var x: const *s32 = &ax
    var y = cast #unconst (*u8) x
    #assert(#typeof(y) == *u8)
}

func semaTest005()
{
    var ax: s32
    var x = cast([*]s32) &ax
    var y = cast([*]u8) x
    #assert(#typeof(y) == [*]u8)
}

func semaTest006()
{
    var a: [2] s32
    var p1: *s32 = a
    var p2: const *s32 = a
}

func semaTest007()
{
    var a: [2] s32
    var p1: *void = a
}

func semaTest008()
{
    var str1: string = "abc"
    let data1 = @dataof(str1)
    let data2: const [*] void = data1
}

func semaTest009()
{
    var a: typeinfo = #typeof(s32)
    var b = cast(const *u8) a
    var c = cast(const *void) a
}

func semaTest010()
{
    var ax: s32
    var x: const *s32 = &ax
    var y = cast(const *u8) x
    #assert(#typeof(y) == const *u8)
}

func semaTest011()
{
    var ax: s32
    var x = cast(const [*]s32) &ax
    var y = cast(const [*]u8) x
    #assert(#typeof(y) == const [*]u8)
}

func semaTest012()
{
    var a: [2] s32
    var p1: const *void = a
}

struct RawPointerCast
{
    x: u32
}

func acceptConstVoidPointer(ptr: const [*] void)
{
    #assert(#typeof(ptr) == const [*] void)
}

func semaTest013()
{
    var value: RawPointerCast
    acceptConstVoidPointer(value)
}

#[Swag.Strict]
alias StrictHandle = #null const *void

func strictHandleSource()->StrictHandle
{
    return null
}

func semaTest014()
{
    var handle: StrictHandle = null
    #assert(#typeof(handle) == StrictHandle)

    var handleFromRaw: StrictHandle = cast(#null const *void) strictHandleSource()
    #assert(#typeof(handleFromRaw) == StrictHandle)
}

func semaTest015()
{
    let text = "hello"
    let ptr  = cast(const [*] u8) text
    #assert(#typeof(ptr) == const [*] u8)
}

func semaTest016()
{
    var data: [4] s32
    var index: u64 = 2

    #assert(#typeof(&data[0]) == *s32)
    #assert(#typeof(&data[index]) == *s32)
}

func semaTest017()
{
    const data: [4] s32 = [1, 2, 3, 4]

    #assert(#typeof(&data[0]) == const *s32)
}

func semaTest018()
{
    var data: [4] u8
    let cstr = cast(cstring) &data[0]

    #assert(#typeof(cstr) == cstring)
}
