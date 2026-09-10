#global private

// A '!' on a value the flow already proved present is a tolerated pass-through, and it is
// reported: the guard it costs can never fire.
struct Node
{
    value: s32
}

func proven(node: *Node?)->s32
{
    if node == null do
        return 0
    return node!.value     // swc-expected-warning {{sema_warn_notnull_already_proven}}
}

// A nullable value with no proof still needs the assertion, and is not reported.
func needed(node: *Node?)->s32
{
    return node!.value
}
