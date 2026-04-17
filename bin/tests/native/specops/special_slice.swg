#global fileprivate

struct RuntimeSliceBox
{
    values:     [5] s32
    sliceCalls: s32
    lastLow:    u64
    lastUp:     u64
}

impl RuntimeSliceBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd opCount() -> u64
    {
        return 5
    }

    #[Swag.Overload, Swag.NoInline]
    mtd opSlice(low, up: u64) -> [..] s32
    {
        .sliceCalls += 1
        .lastLow = low
        .lastUp = up
        return @mkslice(&.values[low], (up + 1) - low)
    }
}

struct RuntimeStringSliceBox
{
    bytes: [6] u8
}

impl RuntimeStringSliceBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd const opCount() -> u64
    {
        return 6
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opSlice(low, up: u64) -> string
    {
        return @mkstring(&.bytes[low], (up + 1) - low)
    }
}

struct RuntimeSliceHolder
{
    value: RuntimeSliceBox
}

#test
{
    var box = RuntimeSliceBox{values: [10, 20, 30, 40, 50]}
    let slice = box[1 to 3]

    #assert(#typeof(slice) == [..] s32)
    @assert(@countof(slice) == 3)
    @assert(slice[0] == 20)
    @assert(slice[1] == 30)
    @assert(slice[2] == 40)
    @assert(box.sliceCalls == 1)
    @assert(box.lastLow == 1)
    @assert(box.lastUp == 3)
}

#test
{
    var box = RuntimeSliceBox{values: [10, 20, 30, 40, 50]}
    let slice = box[1 until 3]

    @assert(@countof(slice) == 2)
    @assert(slice[0] == 20)
    @assert(slice[1] == 30)
    @assert(box.sliceCalls == 1)
    @assert(box.lastLow == 1)
    @assert(box.lastUp == 2)
}

#test
{
    var box = RuntimeSliceBox{values: [10, 20, 30, 40, 50]}
    let slice = box[ to 2]

    @assert(@countof(slice) == 3)
    @assert(slice[0] == 10)
    @assert(slice[1] == 20)
    @assert(slice[2] == 30)
    @assert(box.lastLow == 0)
    @assert(box.lastUp == 2)
}

#test
{
    var box = RuntimeSliceBox{values: [10, 20, 30, 40, 50]}
    let slice = box[2 to ]

    @assert(@countof(slice) == 3)
    @assert(slice[0] == 30)
    @assert(slice[1] == 40)
    @assert(slice[2] == 50)
    @assert(box.lastLow == 2)
    @assert(box.lastUp == 4)
}

#test
{
    var box = RuntimeSliceBox{values: [10, 20, 30, 40, 50]}
    let slice = box[ to ]

    @assert(@countof(slice) == 5)
    @assert(slice[0] == 10)
    @assert(slice[4] == 50)
    @assert(box.lastLow == 0)
    @assert(box.lastUp == 4)
}

#test
{
    var holder = RuntimeSliceHolder{value: RuntimeSliceBox{values: [10, 20, 30, 40, 50]}}
    let slice = holder.value[1 until 4]

    @assert(@countof(slice) == 3)
    @assert(slice[0] == 20)
    @assert(slice[1] == 30)
    @assert(slice[2] == 40)
    @assert(holder.value.sliceCalls == 1)
    @assert(holder.value.lastLow == 1)
    @assert(holder.value.lastUp == 3)
}

#test
{
    const box = RuntimeStringSliceBox{bytes: [115'u8, 116'u8, 114'u8, 105'u8, 110'u8, 103'u8]}
    let middle = box[1 until 5]
    let tail = box[2 to ]
    let head = box[ to 2]

    #assert(#typeof(middle) == string)
    @assert(middle == "trin")
    @assert(tail == "ring")
    @assert(head == "str")
}
