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
    const C = 52
}

#assert(AA.C == 52)

impl AA
{
    mtd toto() {}
    mtd titi(x: s32) {}
}
