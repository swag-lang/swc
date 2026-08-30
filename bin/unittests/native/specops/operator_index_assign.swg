#global private

struct RuntimeIndexAssignBox
{
    values: [2] s32
    reads:  s32
    writes: s32
    shifts: s32
}

impl RuntimeIndexAssignBox
{
    #[Swag.NoInline]
    mtd opIndex(index: s32)->s32
    {
        .reads += 1
        return .values[index]
    }

    #[Swag.NoInline]
    mtd(op: Swag.Operator) opIndexAssign(index: s32, value: s32)
        where op == .AddAssign or op == .MulAssign
    {
        .writes += 1
        #static switch op
        {
        case .AddAssign:
            .values[index] += value

        case .MulAssign:
            .values[index] *= value

        }
    }

    #[Swag.NoInline]
    mtd(op: Swag.Operator) opIndexAssign(index: s32, value: u32)
        where op == .ShlAssign
    {
        .shifts        += 1
        .values[index] <<= #wrap value
    }
}

struct RuntimeWriteOnlyIndexAssignBox
{
    first:  s32
    second: s32
    writes: s32
}

impl RuntimeWriteOnlyIndexAssignBox
{
    #[Swag.NoInline]
    mtd(op: Swag.Operator) opIndexAssign(index: s32, value: s32)
        where op == .AddAssign
    {
        .writes += 1
        if index == 0 do
            .first += value
        else do
            .second += value
    }
}

struct RuntimeRefIndexAssignBox
{
    values: [2] s32
    reads:  s32
    writes: s32
}

impl RuntimeRefIndexAssignBox
{
    #[Swag.NoInline]
    mtd opIndexPtr(index: s32)->*s32
    {
        .reads += 1
        return &.values[index]
    }

    #[Swag.NoInline]
    mtd(op: Swag.Operator) opIndexAssign(index: s32, value: s32)
        where op == .AddAssign
    {
        .writes        += 1
        .values[index] += value
    }
}

struct RuntimeMultiIndexAssignBox
{
    values: [4] s32
    reads:  s32
    writes: s32
}

impl RuntimeMultiIndexAssignBox
{
    #[Swag.NoInline]
    mtd opIndexPtr(row: s32, col: s32)->*s32
    {
        .reads += 1
        return &.values[row * 2 + col]
    }

    #[Swag.NoInline]
    mtd(op: Swag.Operator) opIndexAssign(row: s32, col: s32, value: s32)
        where op == .AddAssign
    {
        .writes                += 1
        .values[row * 2 + col] += value
    }
}

struct RuntimeIndexAssignHolder
{
    value:     RuntimeIndexAssignBox
    writeOnly: RuntimeWriteOnlyIndexAssignBox
}

#test
{
    var box = RuntimeIndexAssignBox{values: [2, 3]}
    box[0] += 5

    Swag.assert(box.values[0] == 7)
    Swag.assert(box.values[1] == 3)
    Swag.assert(box.writes == 1)
    Swag.assert(box.shifts == 0)
    Swag.assert(box.reads == 0)

    let observed = box[0]
    Swag.assert(observed == 7)
    Swag.assert(box.reads == 1)
}

#test
{
    var box = RuntimeIndexAssignBox{values: [2, 3]}
    box[1] *= 4

    Swag.assert(box.values[0] == 2)
    Swag.assert(box.values[1] == 12)
    Swag.assert(box.writes == 1)
    Swag.assert(box.shifts == 0)
    Swag.assert(box.reads == 0)
}

#test
{
    var box = RuntimeIndexAssignBox{values: [3, 5]}
    box[0] <<= 2'u32

    Swag.assert(box.values[0] == 12)
    Swag.assert(box.values[1] == 5)
    Swag.assert(box.writes == 0)
    Swag.assert(box.shifts == 1)
    Swag.assert(box.reads == 0)
}

#test
{
    var holder = RuntimeIndexAssignHolder{
        value: RuntimeIndexAssignBox{values: [1, 10]},
        writeOnly: RuntimeWriteOnlyIndexAssignBox{first: 4, second: 9}
        }

    holder.value[1]     += 6
    holder.writeOnly[0] += 7

    Swag.assert(holder.value.values[0] == 1)
    Swag.assert(holder.value.values[1] == 16)
    Swag.assert(holder.value.writes == 1)
    Swag.assert(holder.value.shifts == 0)
    Swag.assert(holder.value.reads == 0)

    Swag.assert(holder.writeOnly.first == 11)
    Swag.assert(holder.writeOnly.second == 9)
    Swag.assert(holder.writeOnly.writes == 1)
}

#test
{
    var box = RuntimeRefIndexAssignBox{values: [10, 20]}
    box[0] += 7

    Swag.assert(box.values[0] == 17)
    Swag.assert(box.values[1] == 20)
    Swag.assert(box.writes == 1)
    Swag.assert(box.reads == 0)

    let observed = box[0]
    Swag.assert(observed == 17)
    Swag.assert(box.reads == 1)
}

#test
{
    var box = RuntimeMultiIndexAssignBox{values: [1, 2, 3, 4]}
    box[0, 1] += 8

    Swag.assert(box.values[0] == 1)
    Swag.assert(box.values[1] == 10)
    Swag.assert(box.writes == 1)
    Swag.assert(box.reads == 0)
}
