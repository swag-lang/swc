#global private

struct Node
{
    next: *Node
}

const NODE = cast(const *Swag.TypeInfoStruct) #typeof(Node)
#assert(NODE.fields.count == 1)
#assert(NODE.fields[0].name == "next")
#assert(NODE.fields[0].pointedType == *Node)

const NEXT = cast(#null const *Swag.TypeInfoPointer) NODE.fields[0].pointedType
#assert(NEXT.pointedType == Node)

func semaTest001()
{
    const node = cast(const *Swag.TypeInfoStruct) #typeof(Node)
    #assert(node.fields.count == 1)
    const next = cast(#null const *Swag.TypeInfoPointer) node.fields[0].pointedType
    const ok   = next.pointedType == Node
}
