#global private

struct DataOfSpecBuffer
{
    data: [3] s32
}

impl DataOfSpecBuffer
{
    mtd opData()->[*] s32
    {
        return &.data[0]
    }
}

struct ConstDataOfSpecBuffer
{
    data: [2] u8
}

impl ConstDataOfSpecBuffer
{
    mtd const opData()->const [*] u8
    {
        return &.data[0]
    }
}

func semaTest001()
{
    var arr0: [3] s32
    var a:    [..] s32 = arr0
    var b              = a.buffer
    #assert(#typeof(b) == [*] s32)

    var c: string = "x"
    var d         = c.buffer
    #assert(#typeof(d) == const [*] u8)

    var ebuf: [2] u8  = ['x'u8, 0]
    var e:    cstring = cast(cstring) &ebuf[0]
    var f             = e.buffer
    #assert(#typeof(f) == const [*] u8)

    var g: [5] s32
    var h = g.buffer
    #assert(#typeof(h) == [*] s32)

    var i: any = 0's32
    var j      = i.buffer
    #assert(#typeof(j) == [*] void)
}

func semaTest002()
{
    var s: string = "abc"
    var p         = s.buffer
    Swag.assert(p[0] == 'a')
    Swag.assert(p[1] == 'b')
    Swag.assert(p[2] == 'c')
}

func semaTest003()
{
    var arr: [3] u8 = [1, 2, 3]
    var p           = arr.buffer
    Swag.assert(p[0] == 1'u8)
    Swag.assert(p[1] == 2'u8)
    Swag.assert(p[2] == 3'u8)
}

func semaTest004()
{
    var s: string? = null
    var p          = s.buffer
    #assert(#typeof(p) == const [*] u8)
}

func semaTest005()
{
    var arr: [2] s32 = [1, 2]
    var p            = arr.buffer
    p[0] = 7
    Swag.assert(arr[0] == 7)
}

func semaTest006()
{
    const s: string = "abc"
    const p         = s.buffer
    #assert(p != null)
    #assert(p[] == 'a'u8)
}

func semaTest007()
{
    const s: const [..] u8 = cast(const [..] u8) "abc"
    const p                = s.buffer
    #assert(p != null)
    #assert(p[] == 'a'u8)
}

func semaTest008()
{
    const arr: [2] s32 = [7, 9]
    const p            = arr.buffer
    #assert(p != null)
    #assert(p[] == 7)
}

func semaTest009()
{
    var value: DataOfSpecBuffer = {data: [4, 5, 6]}
    var p = value.buffer
    #assert(#typeof(p) == [*] s32)
    p[1] = 42
    Swag.assert(value.data[0] == 4)
    Swag.assert(value.data[1] == 42)
    Swag.assert(value.data[2] == 6)
}

func semaTest010()
{
    const value: ConstDataOfSpecBuffer = {data: [7'u8, 9'u8]}
    let p = value.buffer
    #assert(#typeof(p) == const [*] u8)
    Swag.assert(p[] == 7'u8)
    Swag.assert(p[1] == 9'u8)
}
