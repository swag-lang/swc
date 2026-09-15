#global private

#[Swag.DynCast]
struct Cycle { using next: *Cycle? }
struct Unrelated { value: s32 }
struct CycleLeaf { value: s32 = 42 }
struct CycleHolder { using cycle: *Cycle; using leaf: CycleLeaf }

func query(target, source: typeinfo)->bool => cast #try(target) source != null

#assert(cast #try(Unrelated) Cycle == null)
#assert(cast #try(CycleLeaf) CycleHolder != null)

#test
{
    var first:  Cycle
    var second: Cycle
    first.next  = &second
    second.next = &first
    let boxed: any = &first
    Swag.assert(cast #try(*Unrelated) boxed == null)
    Swag.assert(cast #try(*Cycle) boxed == &first)
    Swag.assert(not query(Unrelated, Cycle))
}

#test
{
    var node: Cycle
    node.next = &node
    let boxed: any = &node
    Swag.assert(cast #try(*Unrelated) boxed == null)
}

#test
{
    var node: Cycle
    node.next = &node
    var holder     = CycleHolder{cycle: &node}
    let boxed: any = &holder
    Swag.assert(cast #try(*CycleLeaf) boxed == &holder.leaf)
}
