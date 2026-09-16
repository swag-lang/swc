#global private

#[Swag.DynCast]
struct Cycle { using next: *Cycle? }
struct Unrelated { value: s32 }
struct CycleLeaf { value: s32 = 42 }
struct CycleHolder { using cycle: *Cycle; using leaf: CycleLeaf }

func query(target, source: typeinfo)->bool => source is target

#assert(not (Cycle is Unrelated))
#assert(CycleHolder is CycleLeaf)

#test
{
    var first:  Cycle
    var second: Cycle
    first.next  = &second
    second.next = &first
    let boxed: any = &first
    Swag.assert(not (boxed is Unrelated))
    Swag.assert(cast #try(*Cycle) boxed == &first)
    Swag.assert(not query(Unrelated, Cycle))
}

#test
{
    var node: Cycle
    node.next = &node
    let boxed: any = &node
    Swag.assert(not (boxed is Unrelated))
}

#test
{
    var node: Cycle
    node.next = &node
    var holder     = CycleHolder{cycle: &node}
    let boxed: any = &holder
    Swag.assert(cast #try(*CycleLeaf) boxed == &holder.leaf)
}
