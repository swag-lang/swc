#global internal

const A = true
const B = A orelse false
#assert(B)

const C: string = null
const D = C orelse "d"
#assert(D == "d")

const E: string = "e"
const F = E orelse "f"
#assert(F == "e")

// Integer coalescing
const G: s32 = 0
const H = G orelse 42
#assert(H == 42)

const I: s32 = 7
const J = I orelse 42
#assert(J == 7)

// Slice coalescing
const S0: const [..] u8 = null
const S1 = S0 orelse "abc"
#assert(#typeof(S1) == const [..] u8)
#assert(S1[0] == 'a')
#assert(S1[1] == 'b')
#assert(S1[2] != 'd')

enum NullCEnum { A, B }

// Left must be convertible to bool
#test
{
    const e = NullCEnum.A
    const r = e orelse NullCEnum.B // swc-expected-error {{sema_err_binary_operand_type}}
}

// Right side must be castable to left side
#test
{
    const s: string = null
    const v = s orelse 1 // swc-expected-error {{sema_err_cannot_cast}}
}

// Both sides must be values
#test { var a = s32 orelse 0 } // swc-expected-error {{sema_err_not_value_expr}}
#test { var b = 0 orelse s32 } // swc-expected-error {{sema_err_not_value_expr}}
