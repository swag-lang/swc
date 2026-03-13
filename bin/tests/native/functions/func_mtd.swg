#global fileprivate // swc-option suite-test

struct A {}
impl A
{
    mtd toto() {}

    mtd titi() { toto(me) }
    mtd tata() { me.toto() }
}
