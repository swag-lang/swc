#global fileprivate // swc-option sema-only

struct Node
{
    next: *Node
}

const NODE = cast(const *Swag.TypeInfoStruct) #typeof(Node)
#assert(@countof(NODE.fields) == 1)
#assert(NODE.fields[0].name == "next")
#assert(NODE.fields[0].pointedType == *Node)

const NEXT = cast(const *Swag.TypeInfoPointer) NODE.fields[0].pointedType
#assert(NEXT.pointedType == Node)

#test
{
    const node = cast(const *Swag.TypeInfoStruct) #typeof(Node)
    #assert(@countof(node.fields) == 1)
    const next = cast(const *Swag.TypeInfoPointer) node.fields[0].pointedType
    const ok   = next.pointedType == Node
}
