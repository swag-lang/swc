#global fileprivate // swc-option suite-test

struct A {}
func titi(a: &A) {}
#test
{
    var a: A
    titi(&a)
}

func tata(a: const &A) {}
#test
{
    var a: A
    tata(a)
}



