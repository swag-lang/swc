#global fileprivate

struct RuntimeIndexAssignBox
{
    values: [2] s32
    reads:  s32
    writes: s32
    shifts: s32
}

impl RuntimeIndexAssignBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd opIndex(index: s32) -> s32
    {
        .reads += 1
        return .values[index]
    }

    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) opIndexAssign(index: s32, value: s32)
    {
        .writes += 1
        #if op == "+=" do
            .values[index] += value
        #elif op == "*=" do
            .values[index] *= value
        #else do
            #error("unsupported opIndexAssign op [[" ++ op ++ "]]")
    }

    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) opIndexAssign(index: s32, value: u32)
    {
        .shifts += 1
        #if op == "<<=" do
            .values[index] <<= #wrap value
        #else do
            #error("unsupported opIndexAssign op [[" ++ op ++ "]]")
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
    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) opIndexAssign(index: s32, value: s32)
    {
        .writes += 1
        #if op == "+=" do
            if index == 0 do
                .first += value
            else do
                .second += value
        #else do
            #error("unsupported opIndexAssign op [[" ++ op ++ "]]")
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
    #[Swag.Overload, Swag.NoInline]
    mtd opIndex(index: s32) -> &s32
    {
        .reads += 1
        return &.values[index]
    }

    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) opIndexAssign(index: s32, value: s32)
    {
        .writes += 1
        #if op == "+=" do
            .values[index] += value
        #else do
            #error("unsupported opIndexAssign op [[" ++ op ++ "]]")
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
    #[Swag.Overload, Swag.NoInline]
    mtd opIndex(row: s32, col: s32) -> &s32
    {
        .reads += 1
        return &.values[row * 2 + col]
    }

    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) opIndexAssign(row: s32, col: s32, value: s32)
    {
        .writes += 1
        #if op == "+=" do
            .values[row * 2 + col] += value
        #else do
            #error("unsupported opIndexAssign op [[" ++ op ++ "]]")
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

    @assert(box.values[0] == 7)
    @assert(box.values[1] == 3)
    @assert(box.writes == 1)
    @assert(box.shifts == 0)
    @assert(box.reads == 0)

    let observed = box[0]
    @assert(observed == 7)
    @assert(box.reads == 1)
}

#test
{
    var box = RuntimeIndexAssignBox{values: [2, 3]}
    box[1] *= 4

    @assert(box.values[0] == 2)
    @assert(box.values[1] == 12)
    @assert(box.writes == 1)
    @assert(box.shifts == 0)
    @assert(box.reads == 0)
}

#test
{
    var box = RuntimeIndexAssignBox{values: [3, 5]}
    box[0] <<= 2'u32

    @assert(box.values[0] == 12)
    @assert(box.values[1] == 5)
    @assert(box.writes == 0)
    @assert(box.shifts == 1)
    @assert(box.reads == 0)
}

#test
{
    var holder = RuntimeIndexAssignHolder{
        value:     RuntimeIndexAssignBox{values: [1, 10]},
        writeOnly: RuntimeWriteOnlyIndexAssignBox{first: 4, second: 9},
    }

    holder.value[1] += 6
    holder.writeOnly[0] += 7

    @assert(holder.value.values[0] == 1)
    @assert(holder.value.values[1] == 16)
    @assert(holder.value.writes == 1)
    @assert(holder.value.shifts == 0)
    @assert(holder.value.reads == 0)

    @assert(holder.writeOnly.first == 11)
    @assert(holder.writeOnly.second == 9)
    @assert(holder.writeOnly.writes == 1)
}

#test
{
    var box = RuntimeRefIndexAssignBox{values: [10, 20]}
    box[0] += 7

    @assert(box.values[0] == 17)
    @assert(box.values[1] == 20)
    @assert(box.writes == 1)
    @assert(box.reads == 0)

    let observed = box[0]
    @assert(observed == 17)
    @assert(box.reads == 1)
}

#test
{
    var box = RuntimeMultiIndexAssignBox{values: [1, 2, 3, 4]}
    box[0, 1] += 8

    @assert(box.values[0] == 1)
    @assert(box.values[1] == 10)
    @assert(box.writes == 1)
    @assert(box.reads == 0)
}
