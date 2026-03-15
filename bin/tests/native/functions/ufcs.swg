#global fileprivate // swc-option suite-test

struct A {}

impl A
{
    mtd toto(a: s32) {}
    mtd const titi(a: s32) {}
    func tata(me, a: s32) {}

    mtd titi()
    {
        me.toto(3)
        .toto(4)
    }
}

#test
{
    var a: *A
    a.toto(1)
    A.toto(a, 2)
}

#test
{
    var a: A
    a.toto(1)
    a.titi(10)
    var b: *A
    b.toto(2)
}

#test
{
    var a: A
    a.tata(2)
    A.tata(&a, 3)
}

