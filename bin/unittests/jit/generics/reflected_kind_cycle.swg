#global private

struct Pool
{
    count: s32
}

impl Pool
{
    // Leaf's full descriptor would need Holder and Pool before this method can be declared.
    #static if #typeof(#type Leaf).kind == .Struct
    {
        mtd leafKind()->s32 => 42
    }
}

struct Leaf
{
    owner: *Holder?
}

struct Holder
{
    items: Pool
}

#test
{
    var holder: Holder
    Swag.require(holder.items.leafKind() == 42)
}
