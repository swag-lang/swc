#global private

struct A {}
impl A
{
    mtd toto() {}

    mtd titi() { toto(me) }
    mtd tata() { me.toto() }
}
