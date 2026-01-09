#global internal

struct AA
{
    x: s32
}

impl AA
{
    const A = 52
}

impl AA
{
    const B = A
    #assert(B == 52)
}

//#assert(AA.B == 52)