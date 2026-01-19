#global internal

struct A {}
func titi(a: &A) {}
#test
{
    var a: A
    titi(&a)
}