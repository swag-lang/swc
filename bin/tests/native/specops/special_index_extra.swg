#global fileprivate

// ============================================================================
// opIndex: mutation through returned reference
// ============================================================================

struct RuntimeRefMutBox
{
    buffer: [3] s32
}

impl RuntimeRefMutBox
{
    #[Swag.NoInline]
    mtd opIndex(index: s32) -> &s32
    {
        return &.buffer[index]
    }
}

// Test: read through opIndex reference
#test
{
    var box = RuntimeRefMutBox{buffer: [10, 20, 30]}
    let v0 = box[0]
    let v1 = box[1]
    let v2 = box[2]

    @assert(v0 == 10)
    @assert(v1 == 20)
    @assert(v2 == 30)
}

#test
{
    var box = RuntimeRefMutBox{buffer: [10, 20, 30]}
    box[1] = 99
    @assert(box.buffer[1] == 99)
}

#test
{
    var box = RuntimeRefMutBox{buffer: [5, 10, 15]}
    box[0] += 100
    @assert(box.buffer[0] == 105)
}

// ============================================================================
// opIndex: overloaded index types (s32 key and u64 key)
// ============================================================================

struct RuntimeMultiKeyBox
{
    data:     [4] s32
    s32Reads: s32
    u64Reads: s32
}

impl RuntimeMultiKeyBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd opIndex(index: s32) -> s32
    {
        .s32Reads += 1
        return .data[index]
    }

    #[Swag.Overload, Swag.NoInline]
    mtd opIndex(index: u64) -> s32
    {
        .u64Reads += 1
        return .data[index] * 10
    }
}

// Test: dispatch to s32 overload
#test
{
    var box = RuntimeMultiKeyBox{data: [1, 2, 3, 4]}
    let v = box[1's32]

    @assert(v == 2)
    @assert(box.s32Reads == 1)
    @assert(box.u64Reads == 0)
}

// Test: dispatch to u64 overload
#test
{
    var box = RuntimeMultiKeyBox{data: [1, 2, 3, 4]}
    let v = box[2'u64]

    @assert(v == 30)
    @assert(box.s32Reads == 0)
    @assert(box.u64Reads == 1)
}

// Test: both overloads in same scope
#test
{
    var box = RuntimeMultiKeyBox{data: [10, 20, 30, 40]}
    let a = box[0's32]
    let b = box[3'u64]

    @assert(a == 10)
    @assert(b == 400)
    @assert(box.s32Reads == 1)
    @assert(box.u64Reads == 1)
}

// ============================================================================
// opIndexAffect: overloaded value types
// ============================================================================

struct RuntimeMultiValueBox
{
    intVal:    s32
    floatVal:  f32
    intWrites: s32
    fltWrites: s32
}

impl RuntimeMultiValueBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd opIndexAffect(index: s32, value: s32)
    {
        .intWrites += 1
        .intVal = value + index
    }

    #[Swag.Overload, Swag.NoInline]
    mtd opIndexAffect(index: s32, value: f32)
    {
        .fltWrites += 1
        .floatVal = value + cast(f32) index
    }
}

// Test: dispatch opIndexAffect to s32 value overload
#test
{
    var box = RuntimeMultiValueBox{}
    box[3] = 100's32

    @assert(box.intVal == 103)
    @assert(box.intWrites == 1)
    @assert(box.fltWrites == 0)
}

// Test: dispatch opIndexAffect to f32 value overload
#test
{
    var box = RuntimeMultiValueBox{}
    box[2] = 1.5'f32

    @assert(box.floatVal == 3.5)
    @assert(box.intWrites == 0)
    @assert(box.fltWrites == 1)
}

// Test: both value overloads in same scope
#test
{
    var box = RuntimeMultiValueBox{}
    box[0] = 42's32
    box[1] = 2.5'f32

    @assert(box.intVal == 42)
    @assert(box.floatVal == 3.5)
    @assert(box.intWrites == 1)
    @assert(box.fltWrites == 1)
}

// ============================================================================
// opIndex: const vs mutable overload dispatch
// ============================================================================

struct RuntimeConstMutBox
{
    data:      [2] s32
    mutReads:  s32
}

impl RuntimeConstMutBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd opIndex(index: s32) -> &s32
    {
        .mutReads += 1
        return &.data[index]
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opIndex(index: s32) -> const &s32
    {
        return &.data[index]
    }
}

// Test: mutable receiver calls mutable overload
#test
{
    var box = RuntimeConstMutBox{data: [7, 8]}
    let v = box[0]

    @assert(v == 7)
    @assert(box.mutReads == 1)
}

// Test: const receiver calls const overload
#test
{
    const box = RuntimeConstMutBox{data: [7, 8]}
    let v = box[1]

    @assert(v == 8)
}

#test
{
    var box = RuntimeConstMutBox{data: [1, 2]}
    box[0] = 100
    @assert(box.data[0] == 100)
    @assert(box.mutReads == 1)
}
