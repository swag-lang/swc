#global private

#[Swag.ConstExpr]
func dynamicCollectionComparable(type: typeinfo)->bool
{
    return type.kind != .Func and type.kind != .Lambda
}

struct(T) DynamicRecursiveCollection
{
    items: [..] T?
}

impl DynamicRecursiveCollection
{
    mtd compare(value: T)->s32 where dynamicCollectionComparable(T)
    {
        discard value
        return 0
    }
}

struct DynamicRecursiveNode
{
    children: DynamicRecursiveCollection'(*DynamicRecursiveNode)
}

#test
{
    let type: typeinfo = DynamicRecursiveNode
    Swag.assert(type.kind == .Struct)
}
