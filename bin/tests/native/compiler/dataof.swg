#global fileprivate // 

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

// @dataof returns correct pointer types
#test
{
    var a: [..] s32
    var b = @dataof(a)
    #assert(#typeof(b) == [*] s32)

    var c: string
    var d = @dataof(c)
    #assert(#typeof(d) == const [*] u8)

    var e: cstring
    var f = @dataof(e)
    #assert(#typeof(f) == const [*] u8)

    var g: [5] s32
    var h = @dataof(g)
    #assert(#typeof(h) == [*] s32)

    var i: any
    var j = @dataof(i)
    #assert(#typeof(j) == [*] void)
    @assert(#typeof(b) == [*] s32)
    @assert(#typeof(d) == const [*] u8)
    @assert(#typeof(f) == const [*] u8)
    @assert(#typeof(h) == [*] s32)
    @assert(#typeof(j) == [*] void)
}

// @dataof on string accesses character bytes
#test
{
    var s: string = "abc"
    var p = @dataof(s)
    @assert(p[0] == 'a')
    @assert(p[1] == 'b')
    @assert(p[2] == 'c')
}

// @dataof on fixed array accesses elements
#test
{
    var arr: [3] u8 = [1, 2, 3]
    var p = @dataof(arr)
    @assert(p[0] == 1'u8)
    @assert(p[1] == 2'u8)
    @assert(p[2] == 3'u8)
}

// @dataof on null string returns null
#test
{
    var s: string = null
    var p = @dataof(s)
    #assert(#typeof(p) == const [*] u8)
    @assert(p == null)
}

// @dataof allows mutation of array elements
#test
{
    var arr: [2] s32 = [1, 2]
    var p = @dataof(arr)
    p[0] = 7
    @assert(arr[0] == 7)
}

// @dataof on const string at compile time
#test
{
    const s: string = "abc"
    const p = @dataof(s)
    #assert(p != null)
    #assert(dref p == 'a''u8)
    @assert(p != null)
    @assert(dref p == 'a''u8)
}

// @dataof on const slice at compile time
#test
{
    const s: const [..] u8 = cast(const [..] u8) "abc"
    const p = @dataof(s)
    #assert(p != null)
    #assert(dref p == 'a''u8)
    @assert(p != null)
    @assert(dref p == 'a''u8)
}

// @dataof on const fixed array at compile time
#test
{
    const arr: [2] s32 = [7, 9]
    const p = @dataof(arr)
    #assert(p != null)
    #assert(dref p == 7)
    @assert(p != null)
    @assert(dref p == 7)
}

#test
{
    var value: DataOfSpecBuffer = {data: [4, 5, 6]}
    let p = @dataof(value)
    #assert(#typeof(p) == [*] s32)
    p[1] = 42
    @assert(value.data[0] == 4)
    @assert(value.data[1] == 42)
    @assert(value.data[2] == 6)
}

#test
{
    const value: ConstDataOfSpecBuffer = {data: [7'u8, 9'u8]}
    let p = @dataof(value)
    #assert(#typeof(p) == const [*] u8)
    @assert(dref p == 7'u8)
    @assert(p[1] == 9'u8)
}
