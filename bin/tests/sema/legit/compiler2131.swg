#global fileprivate // swc-option sema-only
#global skip
func(T) toto(v: T) {}

struct(T) A {}

impl A
{
    func titi(me)
    {
        var x: s32
        toto(x)
    }
}

#test
{
    toto'u16(0)
    var v: A'bool
    v.titi()
}
