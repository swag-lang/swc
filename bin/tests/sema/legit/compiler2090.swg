#global fileprivate // swc-option sema-only
#global skip
struct(T) AA {}

impl AA
{
    func toto(me)->{ a: T }
    {
        return {5}
    }
}

//#[Swag.PrintBc]
#test
{
    var x: AA's64
    let v  = x.toto()
    @assert(v.item0 == 5)
}
