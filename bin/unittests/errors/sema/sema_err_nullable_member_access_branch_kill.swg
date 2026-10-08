#global private

struct BranchKillNode
{
    value: s32
}

struct BranchKillOwner
{
    node: *BranchKillNode?
}

func lendBranchKillOwner(owner: *BranchKillOwner) { discard owner }

// A struct lent in one branch loses the proofs about its fields for the code after the `if`,
// whichever branch ran: the other branch keeping its proof does not make it hold afterwards.
func afterLend(lend: bool)->s32
{
    var node:  BranchKillNode = {value: 7}
    var owner: BranchKillOwner = {node: &node}
    if not owner.node do
        return 0

    if lend
    {
        lendBranchKillOwner(&owner)
    }
    else
    {
        discard owner.node.value
    }

    return owner.node.value     // swc-expected-error {{sema_err_nullable_member_access}}
}
