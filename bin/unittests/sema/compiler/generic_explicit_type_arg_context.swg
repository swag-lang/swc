#global export
using Swag

func(T) nullPtr()->#null *T
{
    return null
}

struct(T) ListEntry
{
    value: T
}

struct(T) List {}

impl List
{
    #[Discardable]
    mtd insertAfter(node: #null *ListEntry, value: T)->#null *ListEntry
    {
        discard node
        let n = nullPtr'ListEntry()
        #assert(#typeof(n) == #null *ListEntry'T)
        n.value = value
        return n
    }
}

func semaTestGenericExplicitTypeArgContext()
{
    var values: List's32
    var node:   #null *ListEntry's32 = null
    discard values.insertAfter(node, 1)
}
