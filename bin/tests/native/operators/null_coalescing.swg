#global fileprivate // swc-option suite-test

const A = true
const B = A orelse false
#assert(B)

const C: string = null
const D = C orelse "d"
#assert(D == "d")

const E: string = "e"
const F = E orelse "f"
#assert(F == "e")

const G: s32 = 0
const H = G orelse 42
#assert(H == 42)

const I: s32 = 7
const J = I orelse 42
#assert(J == 7)

const S0: const [..] u8 = null
const S1 = S0 orelse "abc"
#assert(#typeof(S1) == const [..] u8)
#assert(S1[0] == 'a')
#assert(S1[1] == 'b')
#assert(S1[2] != 'd')

enum NullCEnum { A, B }

var NullCoercCounter: s32
var NullCoercValue:   s32 = 33

func fallbackU32()->u32
{
    NullCoercCounter += 1
    return 91'u32
}

func fallbackPointer()->*s32
{
    NullCoercCounter += 1
    return &NullCoercValue
}

func fallbackString()->string
{
    NullCoercCounter += 1
    return "fallback"
}

#test
{
    var a: s32
    @assert((a orelse 11) == 11)
    a = 5
    @assert((a orelse 11) == 5)
}

#test
{
    var p: *s32
    var v: s32 = 10
    @assert((p orelse &v) == &v)
    p = &v
    @assert((p orelse null) == &v)
}

#test
{
    var s: string
    @assert((s orelse "fallback") == "fallback")
    s = "ok"
    @assert((s orelse "fallback") == "ok")
}

#test
{
    NullCoercCounter = 0
    let value = 12'u32 orelse fallbackU32()

    @assert(value == 12'u32)
    @assert(NullCoercCounter == 0)
}

#test
{
    NullCoercCounter = 0
    var ptr: *s32 = null
    let value = ptr orelse fallbackPointer()

    @assert(value == &NullCoercValue)
    @assert(dref value == 33)
    @assert(NullCoercCounter == 1)
}

#test
{
    NullCoercCounter = 0
    var s: string = null
    let value = s orelse fallbackString()

    @assert(value == "fallback")
    @assert(NullCoercCounter == 1)
}

#test
{
    NullCoercCounter = 0
    let s: string = "ok"
    let value = s orelse fallbackString()

    @assert(value == "ok")
    @assert(NullCoercCounter == 0)
}
