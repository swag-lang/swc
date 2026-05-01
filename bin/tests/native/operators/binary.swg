#global fileprivate

#[Swag.Strict]
alias BinaryStrictS32 = s32

#[Swag.Strict]
alias BinaryStrictU32 = u32

#[Swag.Strict]
alias BinaryStrictF32 = f32

#[Swag.Strict]
alias BinaryStrictRune = rune

#[Swag.Strict]
alias BinaryStrictS32Ptr = [*] s32

// Integer arithmetic operators
#test
{
    let a = 40 + 2
    let b = 84 - 42
    let c = 6 * 7
    let d = 84 / 2
    let e = 212 % 85

    #assert(#typeof(a) == s32)
    #assert(#typeof(b) == s32)
    #assert(#typeof(c) == s32)
    #assert(#typeof(d) == s32)
    #assert(#typeof(e) == s32)

    @assert(a == 42)
    @assert(b == 42)
    @assert(c == 42)
    @assert(d == 42)
    @assert(e == 42)
}

// Float arithmetic and type promotion
#test
{
    let a = 40 + 2.5'f64
    let b = 84.0'f32 / 2.0'f32
    let c = 10.5'f64 - 2

    #assert(#typeof(a) == f64)
    #assert(#typeof(b) == f32)
    #assert(#typeof(c) == f64)

    @assert(a == 42.5'f64)
    @assert(b == 42.0'f32)
    @assert(c == 8.5'f64)
}

// Bitwise AND, OR, XOR on u32
#test
{
    let a = 0x3F'u32 & 0x2A'u32
    let b = 0x20'u32 | 0x0A'u32
    let c = 0x7F'u32 ^ 0x55'u32

    #assert(#typeof(a) == u32)
    #assert(#typeof(b) == u32)
    #assert(#typeof(c) == u32)

    @assert(a == 42'u32)
    @assert(b == 42'u32)
    @assert(c == 42'u32)
}

// Shift left and right on u32 and u64
#test
{
    let a = 21'u32 << 1
    let b = 84'u32 >> 1
    let c = 1'u64 << 40
    let d = c >> 20

    #assert(#typeof(a) == u32)
    #assert(#typeof(b) == u32)
    #assert(#typeof(c) == u64)
    #assert(#typeof(d) == u64)

    @assert(a == 42'u32)
    @assert(b == 42'u32)
    @assert(c == 0x0000_0100_0000_0000'u64)
    @assert(d == 0x0000_0000_0010_0000'u64)
}

// Operator precedence and parentheses
#test
{
    let a = 6 + 8 * 5 - 4
    let b = (6 + 8) * (5 - 2)

    @assert(a == 42)
    @assert(b == 42)
}

// 64-bit integer arithmetic
#test
{
    let a = 10000000000's64 + 42's64
    let b = 7'u64 * 6'u64

    #assert(#typeof(a) == s64)
    #assert(#typeof(b) == u64)

    @assert(a == 10000000042's64)
    @assert(b == 42'u64)
}

// Rune bitwise and shift operators behave like int-like unsigned values
#test
{
    let r = 'A''rune
    let a = r & 0x7F
    let b = r | 0x20
    let c = r << 1
    let d = c >> 1

    #assert(#typeof(a) == rune)
    #assert(#typeof(b) == rune)
    #assert(#typeof(c) == rune)
    #assert(#typeof(d) == rune)

    @assert(a == 'A''rune)
    @assert(b == 'a''rune)
    @assert(c == cast(rune) 130'u32)
    @assert(d == 'A''rune)
}

#test
{
    var r = 'A''rune
    let next = r + #wrap 1
    r += #wrap 1

    #assert(#typeof(next) == rune)
    @assert(next == 'B''rune)
    @assert(r == 'B''rune)
}

func binaryStrictAdd(a, b: BinaryStrictS32)->BinaryStrictS32
{
    return a + b
}

func binaryStrictSub(a, b: BinaryStrictS32)->BinaryStrictS32
{
    return a - b
}

func binaryStrictMul(a, b: BinaryStrictS32)->BinaryStrictS32
{
    return a * b
}

func binaryStrictDiv(a, b: BinaryStrictS32)->BinaryStrictS32
{
    return a / b
}

func binaryStrictMod(a, b: BinaryStrictS32)->BinaryStrictS32
{
    return a % b
}

func binaryStrictFloatAdd(a, b: BinaryStrictF32)->BinaryStrictF32
{
    return a + b
}

func binaryStrictBitAnd(a, b: BinaryStrictU32)->BinaryStrictU32
{
    return a & b
}

func binaryStrictBitOr(a, b: BinaryStrictU32)->BinaryStrictU32
{
    return a | b
}

func binaryStrictBitXor(a, b: BinaryStrictU32)->BinaryStrictU32
{
    return a ^ b
}

func binaryStrictShiftLeft(a: BinaryStrictU32, count: BinaryStrictS32)->BinaryStrictU32
{
    return a << count
}

func binaryStrictShiftRight(a: BinaryStrictU32, count: BinaryStrictS32)->BinaryStrictU32
{
    return a >> count
}

func binaryStrictWrapAdd(a, b: BinaryStrictS32)->BinaryStrictS32
{
    return a + #wrap b
}

func binaryStrictPointerOffset(ptr: BinaryStrictS32Ptr, offset: BinaryStrictS32)->BinaryStrictS32Ptr
{
    return ptr + offset
}

func binaryStrictPointerDiff(left, right: BinaryStrictS32Ptr)->s64
{
    return left - right
}

#test
{
    let a = cast(BinaryStrictS32) 40
    let b = cast(BinaryStrictS32) 2
    let u0 = cast(BinaryStrictU32) 0x3F'u32
    let u1 = cast(BinaryStrictU32) 0x2A'u32

    let add = binaryStrictAdd(a, b)
    let sub = binaryStrictSub(cast(BinaryStrictS32) 84, cast(BinaryStrictS32) 42)
    let mul = binaryStrictMul(cast(BinaryStrictS32) 6, cast(BinaryStrictS32) 7)
    let div = binaryStrictDiv(cast(BinaryStrictS32) 84, b)
    let mod = binaryStrictMod(cast(BinaryStrictS32) 212, cast(BinaryStrictS32) 85)
    let fadd = binaryStrictFloatAdd(cast(BinaryStrictF32) 1.5, cast(BinaryStrictF32) 2.5)
    let band = binaryStrictBitAnd(u0, u1)
    let bor = binaryStrictBitOr(cast(BinaryStrictU32) 0x20'u32, cast(BinaryStrictU32) 0x0A'u32)
    let bxor = binaryStrictBitXor(cast(BinaryStrictU32) 0x7F'u32, cast(BinaryStrictU32) 0x55'u32)
    let shl = binaryStrictShiftLeft(cast(BinaryStrictU32) 21'u32, cast(BinaryStrictS32) 1)
    let shr = binaryStrictShiftRight(cast(BinaryStrictU32) 84'u32, cast(BinaryStrictS32) 1)

    #assert(#typeof(add) == BinaryStrictS32)
    #assert(#typeof(sub) == BinaryStrictS32)
    #assert(#typeof(mul) == BinaryStrictS32)
    #assert(#typeof(div) == BinaryStrictS32)
    #assert(#typeof(mod) == BinaryStrictS32)
    #assert(#typeof(fadd) == BinaryStrictF32)
    #assert(#typeof(band) == BinaryStrictU32)
    #assert(#typeof(bor) == BinaryStrictU32)
    #assert(#typeof(bxor) == BinaryStrictU32)
    #assert(#typeof(shl) == BinaryStrictU32)
    #assert(#typeof(shr) == BinaryStrictU32)

    @assert(add == cast(BinaryStrictS32) 42)
    @assert(sub == cast(BinaryStrictS32) 42)
    @assert(mul == cast(BinaryStrictS32) 42)
    @assert(div == cast(BinaryStrictS32) 42)
    @assert(mod == cast(BinaryStrictS32) 42)
    @assert(fadd == cast(BinaryStrictF32) 4.0)
    @assert(band == cast(BinaryStrictU32) 42'u32)
    @assert(bor == cast(BinaryStrictU32) 42'u32)
    @assert(bxor == cast(BinaryStrictU32) 42'u32)
    @assert(shl == cast(BinaryStrictU32) 42'u32)
    @assert(shr == cast(BinaryStrictU32) 42'u32)
}

#test
{
    const add = cast(BinaryStrictS32) 40 + cast(BinaryStrictS32) 2
    const fadd = cast(BinaryStrictF32) 1.5 + cast(BinaryStrictF32) 2.5
    const band = cast(BinaryStrictU32) 0x3F'u32 & cast(BinaryStrictU32) 0x2A'u32
    const shl = cast(BinaryStrictU32) 21'u32 << cast(BinaryStrictS32) 1

    #assert(#typeof(add) == BinaryStrictS32)
    #assert(#typeof(fadd) == BinaryStrictF32)
    #assert(#typeof(band) == BinaryStrictU32)
    #assert(#typeof(shl) == BinaryStrictU32)

    @assert(add == cast(BinaryStrictS32) 42)
    @assert(fadd == cast(BinaryStrictF32) 4.0)
    @assert(band == cast(BinaryStrictU32) 42'u32)
    @assert(shl == cast(BinaryStrictU32) 42'u32)
}

#test
{
    let wrapped = binaryStrictWrapAdd(cast(BinaryStrictS32) 0x7FFF_FFFF, cast(BinaryStrictS32) 1)
    let r = cast(BinaryStrictRune) 'A''rune
    let next = r + #wrap cast(BinaryStrictRune) 1

    #assert(#typeof(wrapped) == BinaryStrictS32)
    #assert(#typeof(next) == BinaryStrictRune)
    @assert(wrapped == cast(BinaryStrictS32) -2147483648)
    @assert(next == cast(BinaryStrictRune) 'B''rune)
}

#test
{
    var data: [3] s32 = [10, 20, 30]
    let base = cast(BinaryStrictS32Ptr) &data[0]
    let one = cast(BinaryStrictS32) 1
    let next = binaryStrictPointerOffset(base, one)

    #assert(#typeof(next) == BinaryStrictS32Ptr)
    @assert(dref next == 20)
    @assert(binaryStrictPointerDiff(next, base) == 1)
}
