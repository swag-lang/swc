#global fileprivate // swc-option sema-only
#global skip
struct AA {}

impl AA
{
    func opAffect(me, v: string) {}
}

#test
{
    var x:  AA
    var ptr = &x
    dref ptr = "toto"
}
