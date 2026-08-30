#global private

// 'orelse' substitutes a MISSING value. Its left operand must be of a type that can carry
// null; a type that never can is rejected, and a zero test is written with a ternary.

const C: #null string = null
const D               = C orelse "d"
#assert(D == "d")

const E: string = "e"
const F         = E orelse "f"
#assert(F == "e")

// Presence, not truthiness: a constant left operand folds the same way a runtime one selects,
// for every nullable-capable family including the ones that answer no condition at all.
#test
{
    let missing:  #null any = null
    let fallback: any       = true
    let resolved            = missing orelse fallback
    Swag.assert(Swag.kindOf(resolved) == bool)
}

const S0: #null const [..] u8 = null
const S1 = S0 orelse "abc"
#assert(#typeof(S1) == const [..] u8)
#assert(S1[0] == 'a')
#assert(S1[1] == 'b')
#assert(S1[2] != 'd')

// The result is guaranteed present, so it drops '#null'.
#assert(#typeof(C orelse "d") == string)

// Out-of-line so `p` is not flow-narrowed at the `orelse` site: a proven non-null left
// side would make the `null` fallback uncastable (and pointless).
func nullCoalescingNullFallback(p: #null *s32)->#null *s32 => p orelse null

func semaTest002()
{
    var p: #null *s32
    var v: s32 = 10
    Swag.assert((p orelse &v) == &v)
    p = &v
    Swag.assert(nullCoalescingNullFallback(p) == &v)
}

func semaTest003()
{
    var s: #null string
    Swag.assert((s orelse "fallback") == "fallback")
    s = "ok"
    Swag.assert((s orelse "fallback") == "ok")
}

// Substituting a zero is a different question, and the ternary answers it.
func semaTest004()
{
    var a: s32
    Swag.assert((a != 0 ? a : 11) == 11)
    a = 5
    Swag.assert((a != 0 ? a : 11) == 5)
}
