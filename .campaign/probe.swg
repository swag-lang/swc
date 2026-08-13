#global private

func bump(p: *u64)
{
    dref p += 1
}

struct Mx
{
    v: u64
}

impl Mx
{
    mtd viaElided()
    {
        bump(&.v)
    }

    mtd viaExplicit()
    {
        bump(&me.v)
    }

    mtd const readElided()->u64
    {
        return .v
    }
}

#test
{
    var m: Mx
    m.viaElided()
    m.viaExplicit()
    @assert(m.readElided() == 2)
}
