#global private

const A = true
const B = A orelse false
#assert(B)

const C: #null string = null
const D               = C orelse "d"
#assert(D == "d")

const E: string = "e"
const F         = E orelse "f"
#assert(F == "e")

const G: s32 = 0
const H      = G orelse 42
#assert(H == 42)

const I: s32 = 7
const J      = I orelse 42
#assert(J == 7)

const K: f32 = 0.0
const L      = K orelse 4.5'f32
#assert(L == 4.5'f32)

const M: f64 = 2.25
const N      = M orelse 4.5'f64
#assert(N == 2.25'f64)

const S0: #null const [..] u8 = null
const S1                      = S0 orelse "abc"
#assert(#typeof(S1) == const [..] u8)
#assert(S1[0] == 'a')
#assert(S1[1] == 'b')
#assert(S1[2] != 'd')

enum NullCEnum { A, B }

func semaTest001()
{
    var a: s32
    @assert((a orelse 11) == 11)
    a = 5
    @assert((a orelse 11) == 5)
}

// Out-of-line so `p` is not flow-narrowed at the `orelse` site: a proven non-null left
// side would make the `null` fallback uncastable (and pointless).
func nullCoalescingNullFallback(p: #null *s32)->#null *s32 => p orelse null

func semaTest002()
{
    var p: #null *s32
    var v: s32 = 10
    @assert((p orelse &v) == &v)
    p = &v
    @assert(nullCoalescingNullFallback(p) == &v)
}

func semaTest003()
{
    var s: #null string
    @assert((s orelse "fallback") == "fallback")
    s = "ok"
    @assert((s orelse "fallback") == "ok")
}
