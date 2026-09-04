#global private

#[Swag.Strict]
alias PointerArithmeticStrictS32Ptr = [*] s32

#[Swag.Strict]
alias PointerArithmeticStrictU8Ptr  = [*] u8

#[Swag.Strict]
alias PointerArithmeticStrictU8     = u8

#test
{
    var x0: s32
    var p:  [*]s32 = cast([*]s32) &x0

    var off1: u8 = 1

    let a = p + 1
    #assert(#typeof(a) == [*]s32)

    let a2 = p + off1
    #assert(#typeof(a2) == [*]s32)

    let b = 1 + p
    #assert(#typeof(b) == [*]s32)

    let b2 = off1 + p
    #assert(#typeof(b2) == [*]s32)

    let c = p - 1
    #assert(#typeof(c) == [*]s32)

    let c2 = p - off1
    #assert(#typeof(c2) == [*]s32)
    Swag.assert((a - p) == 1)
    Swag.assert((a2 - p) == 1)
    Swag.assert((b - p) == 1)
    Swag.assert((b2 - p) == 1)
    Swag.assert((p - c) == 1)
    Swag.assert((p - c2) == 1)
}

#assert(#typeof((cast([*] s32?) null) - (cast([*] s32?) null)) == s64)

#test
{
    var data: [5] s32 = [10, 20, 30, 40, 50]
    let base          = cast([*] s32) &data[0]
    let p2            = base + 2
    let p4            = 4 + base
    let p1            = p4 - 3

    Swag.assert(p2[] == 30)
    Swag.assert(p4[] == 50)
    Swag.assert(p1[] == 20)
    Swag.assert((p4 - base) == 4)
    Swag.assert((p2 - p1) == 1)
}

#test
{
    var data: [4] u8 = [0, 1, 2, 3]
    var ptr          = cast([*] u8) &data[0]
    ptr += 1'u8
    Swag.assert(ptr[0] == 1'u8)
    Swag.assert(ptr[1] == 2'u8)
    ptr -= 1
    Swag.assert(ptr[3] == 3'u8)
}

#test
{
    var data: [5] s32 = [10, 20, 30, 40, 50]
    let base          = cast(PointerArithmeticStrictS32Ptr) &data[0]
    let p2            = base + 2
    let p4            = 4 + base
    let p1            = p4 - 3

    Swag.assert(p2[as s32] == 30)
    Swag.assert(p4[as s32] == 50)
    Swag.assert(p1[as s32] == 20)
    Swag.assert((p4 - base) == 4)
    Swag.assert((p2 - p1) == 1)
}

#test
{
    var data: [4] u8 = [0, 1, 2, 3]
    var ptr          = cast(PointerArithmeticStrictU8Ptr) &data[0]
    ptr += 1'u8
    Swag.assert((cast([*] u8) ptr)[0] == 1'u8)
    Swag.assert((cast([*] u8) ptr)[1] == 2'u8)
    ptr -= 1
    Swag.assert((cast([*] u8) ptr)[3] == 3'u8)
}

#test
{
    var data: [256] u8
    data[255] = 42
    var ptr    = cast([*] u8) &data[0]
    let offset = cast(PointerArithmeticStrictU8) 255
    ptr += offset
    Swag.assert(ptr[] == 42)
    ptr -= offset
    Swag.assert(ptr[255] == 42)
}
