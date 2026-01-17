#global internal

struct A {}

impl A
{
    mtd toto(a: s32) {}
}

#test
{
    var a: *A
    a.toto(1)
    A.toto(a, 2)
}