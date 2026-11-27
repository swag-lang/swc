#global private

enum A
{
    #static if A {
        A = 0
}
    else {
        A = 1
    }
}

enum A
{
    #assert(A)
    B,
    C
}

enum A
{
    #static if A == 0 {
        A = 0
}
    else {
        A = 1
    }
}

enum A
{
    B = 0
    C = 1
}

enum A { B, C }
enum A { B, C }

enum A
{
    B,
    C
}

enum A
{
    B
    C
}

enum
A
{
    B
    C
}

enum A
{
    B = 0,
    C = 1
}

enum A { B = 1_s8 }
enum A { B = 1_s16 }
enum A { B = 1_s32 }
enum A { B = 1_s64 }
enum A { B = 1_u8 }
enum A { B = 1_u16 }
enum A { B = 1_u32 }
enum A { B = 1_u64 }
enum A { B = 1_f32 }
enum A { B = 1_f64 }
enum A { B = 1_T }
enum A { B = 1_TTT_TTT }
enum A { B = 1_bool }
enum A { B = 1_rune }

enum A {}
