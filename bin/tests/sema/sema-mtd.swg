#global internal

struct A {}
impl A
{
    mtd toto() {}

    mtd titi()
    {
        toto(me)
    }
}