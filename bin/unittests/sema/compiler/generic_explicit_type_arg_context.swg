#global export
using Swag

func(T) nullPtr()->*T
{
    return null
}

struct(T) ListEntry
{
    value: T
}

struct(T) List
{
}

impl List
{
    #[Discardable]
    mtd insertAfter(node: *ListEntry, value: T)->*ListEntry
    {
        discard node
        let n = nullPtr'ListEntry()
        #assert(#typeof(n) == *ListEntry'T)
        n.value = value
        return n
    }
}

func semaTestGenericExplicitTypeArgContext()
{
    var values: List's32
    var node: *ListEntry's32 = null
    discard values.insertAfter(node, 1)
}
