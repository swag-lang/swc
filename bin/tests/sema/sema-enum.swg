#global internal

enum AA: u32 { A }
enum BB { A }

enum A1: s8 { A }
enum A2: s16 { A }
enum A3: s32 { A }
enum A4: s64 { A }
enum A5: u8 { A }
enum A6: u16 { A }
enum A7: u32 { A }
enum A8: u64 { A }
enum A9: rune { A = 'A'}
enum A10: bool { A = true }
enum A11: f32 { A = 0 }
enum A12: f64 { A = 0  }
enum A13: string { A = "0" }

enum CC
{
    A = 0,
    #assert(A == 0)
    B,
    #assert(B == 1)
    C = 5,
    #assert(C == 5)
    D,
    #assert(D == 6)
    E = 10,
    #assert(E == 10)
}

enum DD
{
    A = -10,
    #assert(A == -10)
    B,
    #assert(B == -9)
}

enum EE
{
    A,
    #assert(A == 0)
}

#assert(#typeof(BB.A) == BB)
#assert(#typeof(A1.A) == A1)
#assert(#typeof(A9.A) == A9)

#assert(cast(u32) CC.A == 0)
#assert(cast(u32) CC.B == 1)
#assert((cast(s32) CC.C) == 5)
#assert((cast(s32) CC.D) == 6)
#assert(cast(s32) DD.A == -10)
#assert(cast(s32) DD.B == -9)
#assert(cast(rune) A9.A == 'A')
#assert(cast(bool) A10.A == true)
#assert(cast(f32) A11.A == 0)
#assert(cast(f64) A12.A == 0)
#assert(cast(string) A13.A == "0")
#assert(cast(s32) BB.A == 0)

#assert(cast(string) CC.A == "0") // swc-expected-error {{sema_err_cannot_cast}}
#assert(cast #bit (u32) CC.A == 0)
#assert(cast #bit (u64) CC.A == 0) // swc-expected-error {{sema_err_bit_cast_size}}

#assert(cast(s8)  A1.A == 0)
#assert(cast(s16) A2.A == 0)
#assert(cast(s32) A3.A == 0)
#assert(cast(s64) A4.A == 0)
#assert(cast(u8)  A5.A == 0)
#assert(cast(u16) A6.A == 0)
#assert(cast(u32) A7.A == 0)
#assert(cast(u64) A8.A == 0)

#assert(cast(u32) BB.A == 0)
#assert(cast(s32) CC.B == 1)
#assert(cast(u32) CC.B == 1)

#assert(#typeof(CC.A) == CC)
#assert(#typeof(DD.A) == DD)
#assert(#typeof(EE.A) == EE)

#assert(cast(f32) CC.A == 0)
#assert(cast #bit (u16) A10.A == 1) // swc-expected-error {{sema_err_bit_cast_invalid_type}}

enum InitMismatch1: u32 {
  A = -1, // swc-expected-error {{sema_err_signed_unsigned}}
}
enum InitMismatch2: bool {
  A = 1, // swc-expected-error {{sema_err_cannot_cast}}
}

enum Mixed1: s32 {
  A = -2,
  #assert(A == -2)
  B,
  #assert(B == -1)
  C = 10,
  #assert(C == 10)
  D,
  #assert(D == 11)
}

enum SmallRange1: u8 {
  A = 255,
  #assert(A == 255)
  B, // swc-expected-error {{sema_err_literal_overflow}}
}

enum UnsignedNeg: u16 {
  A = -1, // swc-expected-error {{sema_err_signed_unsigned}}
}

enum StartsAtZero: u32 {
  A,
  #assert(A == 0)
  B,
  #assert(B == 1)
}

enum RuneOk: rune {
  A = 'A',
  #assert(A == 'A')
  B = 'B',
  #assert(B == 'B')
}

enum BoolOk: bool {
  T = true,
  #assert(T == true)
  F = false,
  #assert(F == false)
}

enum BoolOk1: bool {
  T = B1, // swc-expected-error {{sema_err_unknown_symbol}}
  #assert(T == true)
  F = false,
  #assert(F == false)
}

enum Test{
    A = 1,
    B = 2,
    C = 3,
}

#assert(#kindof(Test) == s32)

const X = Test.A
#assert(X == 1)
#assert(X == Test.A)
#assert(#typeof(X) == Test)

enum EN { A }
const CA = cast(u32)EN+1 // swc-expected-error {{sema_err_not_value_expr}}
