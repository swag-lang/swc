#global fileprivate

#[Swag.Strict]
alias CompoundStrictS32 = s32

#[Swag.Strict]
alias CompoundStrictU32 = u32

#[Swag.Strict]
alias CompoundStrictF32 = f32

#[Swag.Strict]
alias CompoundStrictS32Ptr = [*] s32

// Arithmetic compound assignment on s32
#test
{
    var a: s32 = 100
    a += 10
    @assert(a == 110)
    a -= 25
    @assert(a == 85)
    a *= 2
    @assert(a == 170)
    a /= 5
    @assert(a == 34)
    a %= 10
    @assert(a == 4)
}

// Bitwise compound assignment on u32
#test
{
    var a: u32 = 0xFF'u32
    a &= 0x0F'u32
    @assert(a == 0x0F'u32)
    a |= 0x30'u32
    @assert(a == 0x3F'u32)
    a ^= 0x15'u32
    @assert(a == 0x2A'u32)
}

// Shift compound assignment on u32
#test
{
    var a: u32 = 1'u32
    a <<= 5
    @assert(a == 32'u32)
    a >>= 2
    @assert(a == 8'u32)
}

// Shift compound assignment on u64
#test
{
    var a: u64 = 1'u64
    a <<= 40
    @assert(a == 0x0000_0100_0000_0000'u64)
    a >>= 20
    @assert(a == 0x0000_0000_0010_0000'u64)
}

// Float compound assignment on f64
#test
{
    var a: f64 = 10.0'f64
    a += 2.5'f64
    @assert(a == 12.5'f64)
    a -= 0.5'f64
    @assert(a == 12.0'f64)
    a *= 3.5'f64
    @assert(a == 42.0'f64)
    a /= 6.0'f64
    @assert(a == 7.0'f64)
}

// Compound assignment on s64
#test
{
    var a: s64 = 1000000000's64
    a += 42's64
    @assert(a == 1000000042's64)
    a -= 1000000000's64
    @assert(a == 42's64)
    a *= 1000000000's64
    @assert(a == 42000000000's64)
    a /= 1000000000's64
    @assert(a == 42's64)
}

func addAssign(a: &s32, b: s32)
{
    a += b
}

func mulAssign(a: &s32, b: s32)
{
    a *= b
}

// Compound assignment through reference parameters
#test
{
    var x: s32 = 10
    addAssign(&x, 32)
    @assert(x == 42)
    mulAssign(&x, 2)
    @assert(x == 84)
}

func addAssignStrict(a: &CompoundStrictS32, b: CompoundStrictS32)
{
    a += b
}

func mulAssignStrict(a: &CompoundStrictS32, b: CompoundStrictS32)
{
    a *= b
}

#test
{
    var i = cast(CompoundStrictS32) 100
    i += cast(CompoundStrictS32) 10
    @assert(i == cast(CompoundStrictS32) 110)
    i -= cast(CompoundStrictS32) 25
    @assert(i == cast(CompoundStrictS32) 85)
    i *= cast(CompoundStrictS32) 2
    @assert(i == cast(CompoundStrictS32) 170)
    i /= cast(CompoundStrictS32) 5
    @assert(i == cast(CompoundStrictS32) 34)
    i %= cast(CompoundStrictS32) 10
    @assert(i == cast(CompoundStrictS32) 4)

    var f = cast(CompoundStrictF32) 10.0
    f += cast(CompoundStrictF32) 2.5
    f *= cast(CompoundStrictF32) 2.0
    @assert(f == cast(CompoundStrictF32) 25.0)

    var bits = cast(CompoundStrictU32) 0xFF'u32
    bits &= cast(CompoundStrictU32) 0x0F'u32
    bits |= cast(CompoundStrictU32) 0x30'u32
    bits ^= cast(CompoundStrictU32) 0x15'u32
    @assert(bits == cast(CompoundStrictU32) 0x2A'u32)

    var shift = cast(CompoundStrictU32) 1'u32
    shift <<= cast(CompoundStrictS32) 5
    shift >>= cast(CompoundStrictS32) 2
    @assert(shift == cast(CompoundStrictU32) 8'u32)

    var throughRef = cast(CompoundStrictS32) 10
    addAssignStrict(&throughRef, cast(CompoundStrictS32) 32)
    mulAssignStrict(&throughRef, cast(CompoundStrictS32) 2)
    @assert(throughRef == cast(CompoundStrictS32) 84)

    var wrapped = cast(CompoundStrictS32) 0x7FFF_FFFF
    wrapped += #wrap cast(CompoundStrictS32) 1
    @assert(wrapped == cast(CompoundStrictS32) -2147483648)

    var wrapShift = cast(CompoundStrictU32) 1'u32
    wrapShift <<= #wrap cast(CompoundStrictS32) 31
    @assert(wrapShift == cast(CompoundStrictU32) 0x8000_0000'u32)
}

#test
{
    var data: [3] s32 = [10, 20, 30]
    var ptr = cast(CompoundStrictS32Ptr) &data[0]
    ptr += cast(CompoundStrictS32) 1
    @assert(dref ptr == 20)
    ptr -= cast(CompoundStrictS32) 1
    @assert(dref ptr == 10)
}
