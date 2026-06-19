#global fileprivate
#assert((true ? 10 : 20) == 10)
#assert((false ? 10 : 20) == 20)
#assert((true ? "true" : "false") == "true")
#assert((false ? "true" : "false") == "false")

#[Swag.Strict]
alias ConditionalStrictF32 = f32

#[Swag.Strict]
alias ConditionalStrictS32 = s32

func chooseConditionalStrictF32(flag: bool)->ConditionalStrictF32
{
    let a = cast(ConditionalStrictF32) 1.5
    let b = cast(ConditionalStrictF32) 2.5
    return flag ? a : b
}

func chooseConditionalStrictS32(flag: bool)->ConditionalStrictS32
{
    let a = cast(ConditionalStrictS32) 11
    let b = cast(ConditionalStrictS32) 22
    return flag ? a : b
}

// Ternary with type promotion and runtime eval
#test
{
    const a = true ? 10's16 : 20's32
    #assert(#typeof(a) == s32)

    const b = false ? 10's16 : 20's32
    #assert(#typeof(b) == s32)
    #assert(b == 20)

    const c = true ? 1.0'f32 : 2.0'f64
    #assert(#typeof(c) == f64)

    const d = true ? 20's32 : 10's16
    #assert(#typeof(d) == s32)
    @assert(a == 10)
    @assert(b == 20)
    @assert(c == 1.0)
    @assert(d == 20)
}

// Ternary with zero as false condition
#test
{
    var a = 0 ? 1 : 2
    @assert(a == 2)

    var b = 0.0'f32 ? 1 : 2
    var c = 1.5'f32 ? 1 : 2
    @assert(b == 2)
    @assert(c == 1)
}

namespace NC{}

#assert((true ? (false ? 1 : 2) : 3) == 2)
#assert((false ? 1 : (true ? 2 : 3)) == 2)

const VAL1 = 10
var var2 = 20
#assert((true ? VAL1 : var2) == 10)

#test
{
    @assert(chooseConditionalStrictF32(true) == cast(ConditionalStrictF32) 1.5)
    @assert(chooseConditionalStrictF32(false) == cast(ConditionalStrictF32) 2.5)
}

#test
{
    const a = true ? cast(ConditionalStrictS32) 11 : cast(ConditionalStrictS32) 22
    const b = false ? cast(ConditionalStrictF32) 1.5 : cast(ConditionalStrictF32) 2.5

    #assert(#typeof(a) == ConditionalStrictS32)
    #assert(#typeof(b) == ConditionalStrictF32)
    @assert(a == cast(ConditionalStrictS32) 11)
    @assert(b == cast(ConditionalStrictF32) 2.5)
    @assert(chooseConditionalStrictS32(true) == cast(ConditionalStrictS32) 11)
    @assert(chooseConditionalStrictS32(false) == cast(ConditionalStrictS32) 22)
}
