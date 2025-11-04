enum A
{
    #assert(A)
    B,
    C,
}

enum A
{
    #if A do
        A = 0
    #else {
        A = 1
    }
}

enum A
{
    #if A == 0 do
        A = 0
    #else {
        A = 1
    }
}

enum A
{
    B = 0
    C = 1
}

enum A { B, C }
enum A { B, C, }

enum A
{
    B,
    C,
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
    C = 1,
}

enum A { B = 1's8, }
enum A { B = 1's16, }
enum A { B = 1's32, }
enum A { B = 1's64, }
enum A { B = 1'u8, }
enum A { B = 1'u16, }
enum A { B = 1'u32, }
enum A { B = 1'u64, }
enum A { B = 1'f32, }
enum A { B = 1'f64, }
enum A { B = 1'T, }
enum A { B = 1'TTT_TTT, }
enum A { B = 1'bool, }
enum A { B = 1'rune, }
