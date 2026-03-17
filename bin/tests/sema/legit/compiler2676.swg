#global fileprivate // swc-option sema-only
#global skip
#test
{
    var ptr = {&toto}
    //@assert(ptr.item0() == 666)
}

func toto(x: s64) => 666
