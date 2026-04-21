#global fileprivate

#test
{
    var x: *s32 = null
    var b: [*]s32 = null

    var v: *s32 = b
    #assert(#typeof(v) == *s32)

    var v2 = cast(*s32) b
    #assert(#typeof(v2) == *s32)

}

#test
{
    var x: *s32 = null
    var b: [*]s32 = null

    var v: *s32 = b
    #assert(#typeof(v) == *s32)

    var v2 = cast(*s32) b
    #assert(#typeof(v2) == *s32)

    var b3 = cast([*]s32) x
    #assert(#typeof(b3) == [*]s32)
}

#test
{
    var x: *s32 = null
    var y = cast(*u8) x
    #assert(#typeof(y) == *u8)
}

#test
{
    var x: const *s32 = null
    var y = cast #unconst (*u8) x
    #assert(#typeof(y) == *u8)
}

#test
{
    var x: [*]s32 = null
    var y = cast([*]u8) x
    #assert(#typeof(y) == [*]u8)
}

#test
{
    var a: [2] s32
    var p1: *s32 = a
    var p2: const *s32 = a
}

#test
{
    var a: [2] s32
    var p1: *void = a
}

#test
{
    var str1: string
    let data1 = @dataof(str1)
    let data2: const [*] void = data1
}

#test
{
    var a: typeinfo
    var b = cast(const *u8) a
    var c = cast(const *void) a
}

#test
{
    var x: const *s32 = null
    var y = cast(const *u8) x
    #assert(#typeof(y) == const *u8)
}

#test
{
    var x: const [*]s32 = null
    var y = cast(const [*]u8) x
    #assert(#typeof(y) == const [*]u8)
}

#test
{
    var a: [2] s32
    var p1: const *void = a
}

#[Swag.Strict]
alias StrictHandle = const *void

#test
{
    var handle: StrictHandle = null
    #assert(#typeof(handle) == StrictHandle)
}

#test
{
    let text = "hello"
    let ptr  = cast(const [*] u8) text
    #assert(#typeof(ptr) == const [*] u8)
}
