#global internal

const A = 0
#assert(#nameof(A) == "A")

enum Test{
    A = 1,
    B = 2,
    C = 3,
}
#assert(#nameof(Test.A) == "A")
#assert(#nameof(Test.B) == "B")
#assert(#nameof(Test.C) == "C")

#assert(#nameof(s8) == "s8")
#assert(#nameof(s16) == "s16")
#assert(#nameof(s32) == "s32")
#assert(#nameof(s64) == "s64")
#assert(#nameof(u8) == "u8")
#assert(#nameof(u16) == "u16")
#assert(#nameof(u64) == "u64")
#assert(#nameof(f32) == "f32")
#assert(#nameof(f64) == "f64")
#assert(#nameof(bool) == "bool")
#assert(#nameof(rune) == "rune")

#assert(#nameof(8) == "8") // swc-expected-error {{sema_err_failed_nameof}}
