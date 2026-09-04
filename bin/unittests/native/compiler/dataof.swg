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

#[Swag.Strict]
alias StrictDataOfArray = [3] s32

#[Swag.Strict]
alias StrictDataOfSlice = [..] s32

impl ConstDataOfSpecBuffer
{
    mtd const opData()->const [*] u8
    {
        return &.data[0]
    }
}

// .buffer returns correct pointer types
#test
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
    Swag.assert(#typeof(b) == [*] s32)
    Swag.assert(#typeof(d) == const [*] u8)
    Swag.assert(#typeof(f) == const [*] u8)
    Swag.assert(#typeof(h) == [*] s32)
    Swag.assert(#typeof(j) == [*] void)
}

// .buffer on string accesses character bytes
#test
{
    var s: string = "abc"
    var p         = s.buffer
    Swag.assert(p[0] == 'a')
    Swag.assert(p[1] == 'b')
    Swag.assert(p[2] == 'c')
}

// .buffer on fixed array accesses elements
#test
{
    var arr: [3] u8 = [1, 2, 3]
    var p           = arr.buffer
    Swag.assert(p[0] == 1'u8)
    Swag.assert(p[1] == 2'u8)
    Swag.assert(p[2] == 3'u8)
}

// .buffer on null string returns null
#test
{
    var s: string? = null
    var p          = s.buffer
    #assert(#typeof(p) == const [*] u8)
    Swag.assert(p == null)
}

// .buffer allows mutation of array elements
#test
{
    var arr: [2] s32 = [1, 2]
    var p            = arr.buffer
    p[0] = 7
    Swag.assert(arr[0] == 7)
}

// .buffer on const string at compile time
#test
{
    const s: string = "abc"
    const p         = s.buffer
    #assert(p != null)
    #assert(p[] == 'a'u8)
    Swag.assert(p != null)
    Swag.assert(p[] == 'a'u8)
}

// .buffer on const slice at compile time
#test
{
    const s: const [..] u8 = cast(const [..] u8) "abc"
    const p                = s.buffer
    #assert(p != null)
    #assert(p[] == 'a'u8)
    Swag.assert(p != null)
    Swag.assert(p[] == 'a'u8)
}

// .buffer on const fixed array at compile time
#test
{
    const arr: [2] s32 = [7, 9]
    const p            = arr.buffer
    #assert(p != null)
    #assert(p[] == 7)
    Swag.assert(p != null)
    Swag.assert(p[] == 7)
}

#test
{
    var value: DataOfSpecBuffer = {data: [4, 5, 6]}
    let p = value.buffer
    #assert(#typeof(p) == [*] s32)
    p[1] = 42
    Swag.assert(value.data[0] == 4)
    Swag.assert(value.data[1] == 42)
    Swag.assert(value.data[2] == 6)
}

#test
{
    const value: ConstDataOfSpecBuffer = {data: [7'u8, 9'u8]}
    let p = value.buffer
    #assert(#typeof(p) == const [*] u8)
    Swag.assert(p[] == 7'u8)
    Swag.assert(p[1] == 9'u8)
}

#test
{
    var value: StrictDataOfArray = cast(StrictDataOfArray) [10, 20, 30]
    let p = value.buffer
    #assert(#typeof(p) == [*] s32)
    p[1] = 44
    Swag.assert(value[0] == 10)
    Swag.assert(value[1] == 44)
    Swag.assert(value[2] == 30)
}

#test
{
    const value: StrictDataOfArray = cast(StrictDataOfArray) [7, 8, 9]
    const p = value.buffer
    #assert(#typeof(p) == const [*] s32)
    #assert(p[] == 7)
    Swag.assert(p[1] == 8)
}

#test
{
    var storage: [4] s32           = [3, 6, 9, 12]
    var value:   StrictDataOfSlice = cast(StrictDataOfSlice) storage
    let p                          = value.buffer
    #assert(#typeof(p) == [*] s32)
    p[2] = 55
    Swag.assert(storage[0] == 3)
    Swag.assert(storage[2] == 55)
    Swag.assert(value[3] == 12)
}
