#global internal

enum A: u32 {}
enum B {}

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
