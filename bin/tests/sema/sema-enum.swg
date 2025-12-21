#global internal

enum A: u32 { A }
enum B { A }
#assert(#typeof(B.A) == B)

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

enum C
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

enum D
{
    A = -10,
    #assert(A == -10)
    B,
    #assert(B == -9)
}

enum E
{
    A,
    #assert(A == 0)
}

#assert(#typeof(A1.A) == A1)
#assert(#typeof(A9.A) == A9)

/*#assert(cast(u32) C.A == 0)
#assert(cast(u32) C.B == 1)
#assert((cast(s32) C.C) == 5)
#assert((cast(s32) C.D) == 6)
#assert(cast(s32) D.A == -10)
#assert(cast(s32) D.B == -9)
#assert(cast(rune) A9.A == 'A')
#assert(cast(bool) A10.A == true)
#assert(cast(f32) A11.A == 0)
#assert(cast(f64) A12.A == 0)
#assert(cast(string) A13.A == "0")
#assert(cast(s32) B.A == 0)*/
