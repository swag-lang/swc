#global private

struct RefIndexContainer
{
    values: [2] s32
}

struct(T) GenericRefIndexContainer
{
    values: [2] T
}

impl RefIndexContainer
{
    mtd const opIndex(index: u64)->const &s32
    {
        return &.values[index]
    }

    mtd opIndex(index: u64)->&s32
    {
        return &.values[index]
    }
}

impl GenericRefIndexContainer
{
    mtd const opIndex(index: u64)->const &T
    {
        return &.values[index]
    }

    mtd opIndex(index: u64)->&T
    {
        return &.values[index]
    }
}

func arrayRefFirst(op: &RefIndexContainer)->s32
{
    return op[0]
}

func arrayRefDouble(op: &RefIndexContainer)->s32
{
    let value = op[0]
    return value + op[0]
}

func arrayRefWrite(op: &RefIndexContainer)
{
    op[0] = 42
}

struct LoopRefIndexContainer
{
    values: [6] s32
}

impl LoopRefIndexContainer
{
    mtd const opIndex(index: u64)->const &s32
    {
        return &.values[index]
    }

    mtd opIndex(index: u64)->&s32
    {
        return &.values[index]
    }

    mtd opIndexSet(index: u64, value: s32)
    {
        .values[index] = value
    }
}

#test
{
    var values = RefIndexContainer{values: [11, 99]}
    @assert(arrayRefFirst(&values) == 11)
}

#test
{
    var values = RefIndexContainer{values: [12, 99]}
    @assert(arrayRefDouble(&values) == 24)
}

#test
{
    var values = RefIndexContainer{values: [1, 2]}
    arrayRefWrite(&values)
    @assert(values[0] == 42)
}

#test
{
    var all = [RefIndexContainer{values: [7, 0]}, RefIndexContainer{values: [13, 0]}]
    @assert(arrayRefFirst(&all[0]) == 7)
    @assert(arrayRefFirst(&all[1]) == 13)
}

#test
{
    func genericFirst(op: &GenericRefIndexContainer's32)->s32
    {
        return op[0]
    }

    var values = GenericRefIndexContainer'(s32){values: [21, 34]}
    @assert(genericFirst(&values) == 21)
}

func refIndexSentinelSum(values: &LoopRefIndexContainer, index: &s32)->s32
{
    var result = 0
    while values[index] != 99
    {
        result += values[index + 1]
        index  += 2
    }

    return result
}

func refIndexAssignAt(values: &LoopRefIndexContainer, index: &s32, value: s32)
{
    values[index] = value
}

func refNestedIndexAssign(values: &LoopRefIndexContainer, index: &s32, value: s32)
{
    values[values[index + 1]] = value
}

#test
{
    var values = LoopRefIndexContainer{values: [7, 11, 13, 17, 99, 0]}
    var index = 0
    @assert(refIndexSentinelSum(&values, &index) == 28)
    @assert(index == 4)
}

#test
{
    var values = LoopRefIndexContainer{values: [5, 8, 13, 21, 34, 55]}
    var index = 1
    refIndexAssignAt(&values, &index, 42)
    @assert(values[1] == 42)
    @assert(index == 1)
}

#test
{
    var values = LoopRefIndexContainer{values: [0, 4, 2, 3, 1, 5]}
    var index = 0
    refNestedIndexAssign(&values, &index, 42)
    @assert(values[4] == 42)
    @assert(index == 0)
}
