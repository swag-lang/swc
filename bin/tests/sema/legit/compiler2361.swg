#global fileprivate // swc-option sema-only
#global skip
struct AA {}

impl AA
{
    func toto(me, x: string, z: ...) {}
}

#test
{
    var v: AA
    v.toto("titi", 10, 20)
}
