#global private

const C: string? = null
const D          = C orelse "d"
#assert(D == "d")

const E: string = "e"
const F         = E orelse "f"
#assert(F == "e")

const S0: const [..] u8? = null
const S1                 = S0 orelse "abc"
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
    Swag.assert((a != 0 ? a : 11) == 11)
    a = 5
    Swag.assert((a != 0 ? a : 11) == 5)
}

// Out-of-line so `p` is not flow-narrowed at the `orelse` site: a proven non-null left
// side would make the `null` fallback uncastable (and pointless).
func nullCoalescingNullFallback(p: *s32?)->*s32? => p orelse null

#test
{
    var p: *s32?
    var v: s32 = 10
    Swag.assert((p orelse &v) == &v)
    p = &v
    Swag.assert(nullCoalescingNullFallback(p) == &v)
}

#test
{
    var s: string?
    Swag.assert((s orelse "fallback") == "fallback")
    s = "ok"
    Swag.assert((s orelse "fallback") == "ok")
}

#test
{
    NullCoercCounter = 0
    let value = 12'u32 != 0 ? 12'u32 : fallbackU32()

    Swag.assert(value == 12'u32)
    Swag.assert(NullCoercCounter == 0)
}

#test
{
    NullCoercCounter = 0
    var ptr: *s32? = null
    let value      = ptr orelse fallbackPointer()

    Swag.assert(value == &NullCoercValue)
    Swag.assert(value[] == 33)
    Swag.assert(NullCoercCounter == 1)
}

#test
{
    NullCoercCounter = 0
    var s: string? = null
    let value      = s orelse fallbackString()

    Swag.assert(value == "fallback")
    Swag.assert(NullCoercCounter == 1)
}

#test
{
    NullCoercCounter = 0
    let s: string = "ok"
    let value     = s orelse fallbackString()

    Swag.assert(value == "ok")
    Swag.assert(NullCoercCounter == 0)
}
