#global internal

enum A: u32 {}
enum A1 {}

enum A2
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
