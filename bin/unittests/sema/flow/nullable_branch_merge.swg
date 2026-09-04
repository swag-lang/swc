#global private

// What holds after an 'if' is what BOTH paths prove. A path that terminates the local flow is
// not one of them, so the surviving path's facts hold alone; a path that proves nothing leaves
// the value nullable, and a proof made inside a nested construct belongs to that construct.

struct NullableBranchMergeItem
{
    value: s32
}

func nullableBranchMergeBoth(flag: bool, left, right: *NullableBranchMergeItem)->s32
{
    var item: *NullableBranchMergeItem?
    if flag do item = left
    else do item = right
    return item.value
}

func nullableBranchMergeBothBraced(flag: bool, left, right: *NullableBranchMergeItem)->s32
{
    var item: *NullableBranchMergeItem?
    if flag
    {
        item = left
    }
    else
    {
        item = right
    }

    return item.value
}

func nullableBranchMergeChain(kind: s32, first, second, third: *NullableBranchMergeItem)->s32
{
    var item: *NullableBranchMergeItem?
    if kind == 0 do item = first
    elif kind == 1 do item = second
    else do item = third
    return item.value
}

// A guard-style exit publishes the surviving path's own proof, not just the condition's.
func nullableBranchMergeGuardElse(flag: bool, item: *NullableBranchMergeItem)->s32
{
    var scan: *NullableBranchMergeItem?
    if flag
    {
        return 0
    }
    else
    {
        scan = item
    }

    return scan.value
}

// One path proves it and the other does not, so the value stays nullable and needs '!'.
func nullableBranchMergeOnlyOne(flag: bool, left: *NullableBranchMergeItem, right: *NullableBranchMergeItem?)->s32
{
    var item: *NullableBranchMergeItem?
    if flag do item = left
    else do item = right
    return item!.value
}

// A nested 'if' runs on one path of its own branch, so the enclosing branch proves nothing.
func nullableBranchMergeNested(outer, inner: bool, left: *NullableBranchMergeItem?, right: *NullableBranchMergeItem)->s32
{
    var item = left
    if outer
    {
        if inner do item = right
    }
    else
    {
        item = right
    }

    return item!.value
}

// A loop body may run zero times, so a proof made inside it does not reach the branch end.
func nullableBranchMergeLoopBody(flag: bool, left: *NullableBranchMergeItem?, right: *NullableBranchMergeItem, count: s32)->s32
{
    var item = left
    if flag
    {
        for count do item = right
    }
    else do item = right
    return item!.value
}

// A path that reassigns a nullable value kills the proof for that path.
func nullableBranchMergeKill(flag: bool, left: *NullableBranchMergeItem, right: *NullableBranchMergeItem?)->s32
{
    var item: *NullableBranchMergeItem? = left
    if flag { item = right }
    else { item = left }
    return item!.value
}

// Without an 'else' the fall-through path proves only what the condition settled, which the
// branch assignment must agree with for the merge to publish anything.
func nullableBranchMergeNoElse(item: *NullableBranchMergeItem?, fallback: *NullableBranchMergeItem)->s32
{
    var scan = item
    if scan == null do
        scan = fallback
    return scan.value
}
