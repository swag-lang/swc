#global fileprivate

// ============================================================================
// opSlice: single-element slice, empty slice, boundary cases
// ============================================================================

struct RuntimeSliceEdgeBox
{
    values:     [5] s32
    sliceCalls: s32
    lastLow:    u64
    lastUp:     u64
}

impl RuntimeSliceEdgeBox
{
    #[Swag.NoInline]
    mtd opCount() -> u64
    {
        return 5
    }

    #[Swag.NoInline]
    mtd opSlice(low, up: u64) -> [..] s32
    {
        .sliceCalls += 1
        .lastLow = low
        .lastUp = up
        return @mkslice(&.values[low], (up + 1) - low)
    }
}

// Test: single-element slice [2 to 2]
#test
{
    var box = RuntimeSliceEdgeBox{values: [10, 20, 30, 40, 50]}
    let slice = box[2 to 2]

    @assert(@countof(slice) == 1)
    @assert(slice[0] == 30)
    @assert(box.sliceCalls == 1)
    @assert(box.lastLow == 2)
    @assert(box.lastUp == 2)
}

// Test: first element only [0 to 0]
#test
{
    var box = RuntimeSliceEdgeBox{values: [10, 20, 30, 40, 50]}
    let slice = box[0 to 0]

    @assert(@countof(slice) == 1)
    @assert(slice[0] == 10)
}

// Test: last element only [4 to 4]
#test
{
    var box = RuntimeSliceEdgeBox{values: [10, 20, 30, 40, 50]}
    let slice = box[4 to 4]

    @assert(@countof(slice) == 1)
    @assert(slice[0] == 50)
}

// Test: single element via 'until' [2 until 3]
#test
{
    var box = RuntimeSliceEdgeBox{values: [10, 20, 30, 40, 50]}
    let slice = box[2 until 3]

    @assert(@countof(slice) == 1)
    @assert(slice[0] == 30)
}

// Test: two-element slice at boundaries [0 to 1]
#test
{
    var box = RuntimeSliceEdgeBox{values: [10, 20, 30, 40, 50]}
    let slice = box[0 to 1]

    @assert(@countof(slice) == 2)
    @assert(slice[0] == 10)
    @assert(slice[1] == 20)
}

// Test: two-element slice at end [3 to 4]
#test
{
    var box = RuntimeSliceEdgeBox{values: [10, 20, 30, 40, 50]}
    let slice = box[3 to 4]

    @assert(@countof(slice) == 2)
    @assert(slice[0] == 40)
    @assert(slice[1] == 50)
}

// Test: multiple slices on same box
#test
{
    var box = RuntimeSliceEdgeBox{values: [1, 2, 3, 4, 5]}
    let head = box[ to 1]
    let mid = box[2 to 2]
    let tail = box[3 to ]

    @assert(@countof(head) == 2)
    @assert(@countof(mid) == 1)
    @assert(@countof(tail) == 2)
    @assert(head[0] == 1)
    @assert(head[1] == 2)
    @assert(mid[0] == 3)
    @assert(tail[0] == 4)
    @assert(tail[1] == 5)
    @assert(box.sliceCalls == 3)
}

// ============================================================================
// opSlice: const overload with computed bounds
// ============================================================================

struct RuntimeConstSliceBox
{
    values: [4] s32
}

impl RuntimeConstSliceBox
{
    #[Swag.NoInline]
    mtd const opCount() -> u64
    {
        return 4
    }

    #[Swag.NoInline]
    mtd const opSlice(low, up: u64) -> [..] s32
    {
        return @mkslice(&.values[low], (up + 1) - low)
    }
}

// Test: const slice from const variable
#test
{
    const box = RuntimeConstSliceBox{values: [100, 200, 300, 400]}
    let slice = box[1 to 2]

    @assert(@countof(slice) == 2)
    @assert(slice[0] == 200)
    @assert(slice[1] == 300)
}

// Test: const full slice
#test
{
    const box = RuntimeConstSliceBox{values: [5, 6, 7, 8]}
    let slice = box[ to ]

    @assert(@countof(slice) == 4)
    @assert(slice[0] == 5)
    @assert(slice[3] == 8)
}
