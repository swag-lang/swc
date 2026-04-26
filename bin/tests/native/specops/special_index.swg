#global fileprivate

struct RuntimeValueIndexBox
{
    first:  s32
    second: s32
    reads:  s32
}

impl RuntimeValueIndexBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd opIndex(index: s32) -> s32
    {
        .reads += 1
        if index == 0 do
            return .first
        return .second
    }
}

struct RuntimeRefIndexBox
{
    buffer: [2] s32
    reads:  s32
}

impl RuntimeRefIndexBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd opIndex(index: s32) -> &s32
    {
        .reads += 1
        return &.buffer[index]
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opIndex(index: s32) -> const &s32
    {
        return &.buffer[index]
    }
}

struct RuntimeMultiIndexBox
{
    values: [4] s32
    reads:  s32
}

impl RuntimeMultiIndexBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd opIndex(row: s32, col: s32) -> s32
    {
        .reads += 1
        return .values[row * 2 + col]
    }
}

struct RuntimeIndexHolder
{
    value: RuntimeValueIndexBox
    refs:  RuntimeRefIndexBox
}

#test
{
    var box = RuntimeValueIndexBox{first: 7, second: 9}
    let a = box[0]
    let b = box[1]

    @assert(a == 7)
    @assert(b == 9)
    @assert(box.reads == 2)
}

#test
{
    var box = RuntimeRefIndexBox{buffer: [3, 5]}
    let v1 = box[1]
    let v0 = box[0]

    @assert(v1 == 5)
    @assert(v0 == 3)
    @assert(box.reads == 2)
}

#test
{
    const box = RuntimeRefIndexBox{buffer: [11, 13]}
    let value = box[0]

    @assert(value == 11)
}

#test
{
    var box = RuntimeMultiIndexBox{values: [10, 20, 30, 40]}
    let value = box[1, 0]

    @assert(value == 30)
    @assert(box.reads == 1)
}

#test
{
    var holder = RuntimeIndexHolder{
        value: RuntimeValueIndexBox{first: 1, second: 2},
        refs:  RuntimeRefIndexBox{buffer: [20, 30]},
    }

    let nested = holder.value[1]
    let nestedRef = holder.refs[0]

    @assert(nested == 2)
    @assert(nestedRef == 20)
    @assert(holder.value.reads == 1)
    @assert(holder.refs.reads == 1)
}

#[Swag.EnumIndex]
enum RuntimeIndexedSlot { First, Second, Third }

#test
{
    const values = [0, 1, 2]
    const first = values[RuntimeIndexedSlot.First]
    @assert(first == 0)

    var index = RuntimeIndexedSlot.Third
    @assert(values[index] == 2)
}
