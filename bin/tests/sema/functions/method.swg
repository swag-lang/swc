#global fileprivate // swc-option sema-only

struct A {}
impl A
{
    mtd toto() {}

    mtd titi() { toto(me) }
    mtd tata() { me.toto() }
}
