#global private

#test
{
    var ax: s32 = 42
    var x: *s32 = &ax

    var y0 = cast(const *s32) x
    #assert(#typeof(y0) == const *s32)
    var x1 = cast #unconst (*s32) y0
    #assert(#typeof(x1) == *s32)
    @assert(y0 == x)
    @assert(x1 == x)
    @assert(dref x1 == 42)
}

#test
{
    var ax: s32 = 7
    var x: *s32 = &ax
    var b = cast([*] s32) x

    var v: *s32 = b
    #assert(#typeof(v) == *s32)

    var v2 = cast(*s32) b
    #assert(#typeof(v2) == *s32)

    @assert(v == x)
    @assert(v2 == x)
}

#test
{
    var ax: s32 = 9
    var x: *s32 = &ax
    var b = cast([*] s32) x

    var v: *s32 = b
    #assert(#typeof(v) == *s32)

    var v2 = cast(*s32) b
    #assert(#typeof(v2) == *s32)

    var b3 = cast([*] s32) x
    #assert(#typeof(b3) == [*] s32)
    @assert(v == x)
    @assert(v2 == x)
    @assert(b3 == x)
}

#test
{
    var ax: s32 = 1
    var x: *s32 = &ax
    var y = cast(*u8) x
    #assert(#typeof(y) == *u8)
    @assert(y == cast(*u8) x)
}

#test
{
    var ax: s32 = 2
    var x: const *s32 = &ax
    var y = cast #unconst (*u8) x
    #assert(#typeof(y) == *u8)
    @assert(y == cast #unconst (*u8) x)
}

#test
{
    var ax: s32 = 3
    var x = cast([*] s32) &ax
    var y = cast([*] u8) x
    #assert(#typeof(y) == [*] u8)
    @assert(y == cast([*] u8) x)
}

#test
{
    var ax: s32 = 4
    var x: *s32 = &ax
    var y = cast([*] u8) x
    #assert(#typeof(y) == [*] u8)

    var x1: u64 = 0x1000
    var v1 = cast(*void) x1

    var x2: u32
    @assert(y == cast([*] u8) x)
    @assert(v1 != null)
    @assert(x2 == 0)
}

#test
{
    var ax: s32 = 5
    var x: const *s32 = &ax
    var y = cast(const *u8) x
    #assert(#typeof(y) == const *u8)
    @assert(y == cast(const *u8) x)
}

#test
{
    var ax: s32 = 6
    var x: const *s32 = &ax
    var y = cast(const *void) x
    #assert(#typeof(y) == const *void)
    @assert(y == cast(const *void) x)
}

#test
{
    var ax: s32 = 8
    var x = cast(const [*] s32) &ax
    var y = cast(const [*] u8) x
    #assert(#typeof(y) == const [*] u8)
    @assert(y == cast(const [*] u8) x)
}

#[Swag.Strict]
alias StrictHandle = #null const *void

struct PointerConstCastBox
{
    value: s32
}

#test
{
    var handle: StrictHandle = null
    @assert(handle == null)
}

#test
{
    let text = "hello"
    let ptr  = cast(const [*] u8) text
    @assert(ptr == @dataof(text))
    @assert(ptr[0] == 'h')
}

#test
{
    const data: [2] u8 = [11'u8, 13'u8]
    let ptr = cast(const [*] u8) data
    #assert(#typeof(ptr) == const [*] u8)
    @assert(ptr[0] == 11'u8)
    @assert(ptr[1] == 13'u8)
}

#test
{
    const value: PointerConstCastBox = {value: 123}
    let ptr = cast(const *PointerConstCastBox) value
    #assert(#typeof(ptr) == const *PointerConstCastBox)
    @assert(ptr.value == 123)
}
