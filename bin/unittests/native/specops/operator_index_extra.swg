#global private

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
    mtd opIndexPtr(index: s32)->*s32
    {
        return &.buffer[index]
    }
}

// Test: read through opIndex reference
#test
{
    var box = RuntimeRefMutBox{buffer: [10, 20, 30]}
    let v0  = box[0]
    let v1  = box[1]
    let v2  = box[2]

    Swag.require(v0 == 10)
    Swag.require(v1 == 20)
    Swag.require(v2 == 30)
}

#test
{
    var box = RuntimeRefMutBox{buffer: [10, 20, 30]}
    box[1] = 99
    Swag.require(box.buffer[1] == 99)
}

#test
{
    var box = RuntimeRefMutBox{buffer: [5, 10, 15]}
    box[0] += 100
    Swag.require(box.buffer[0] == 105)
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
    #[Swag.NoInline]
    mtd opIndex(index: s32)->s32
    {
        .s32Reads += 1
        return .data[index]
    }

    #[Swag.NoInline]
    mtd opIndex(index: u64)->s32
    {
        .u64Reads += 1
        return .data[index] * 10
    }
}

// Test: dispatch to s32 overload
#test
{
    var box = RuntimeMultiKeyBox{data: [1, 2, 3, 4]}
    let v   = box[1's32]

    Swag.require(v == 2)
    Swag.require(box.s32Reads == 1)
    Swag.require(box.u64Reads == 0)
}

// Test: dispatch to u64 overload
#test
{
    var box = RuntimeMultiKeyBox{data: [1, 2, 3, 4]}
    let v   = box[2'u64]

    Swag.require(v == 30)
    Swag.require(box.s32Reads == 0)
    Swag.require(box.u64Reads == 1)
}

// Test: both overloads in same scope
#test
{
    var box = RuntimeMultiKeyBox{data: [10, 20, 30, 40]}
    let a   = box[0's32]
    let b   = box[3'u64]

    Swag.require(a == 10)
    Swag.require(b == 400)
    Swag.require(box.s32Reads == 1)
    Swag.require(box.u64Reads == 1)
}

// ============================================================================
// opIndexSet: overloaded value types
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
    #[Swag.NoInline]
    mtd opIndexSet(index: s32, value: s32)
    {
        .intWrites += 1
        .intVal    = value + index
    }

    #[Swag.NoInline]
    mtd opIndexSet(index: s32, value: f32)
    {
        .fltWrites += 1
        .floatVal  = value + cast(f32, index)
    }
}

// Test: dispatch opIndexSet to s32 value overload
#test
{
    var box = RuntimeMultiValueBox{}
    box[3] = 100's32

    Swag.require(box.intVal == 103)
    Swag.require(box.intWrites == 1)
    Swag.require(box.fltWrites == 0)
}

// Test: dispatch opIndexSet to f32 value overload
#test
{
    var box = RuntimeMultiValueBox{}
    box[2] = 1.5'f32

    Swag.require(box.floatVal == 3.5)
    Swag.require(box.intWrites == 0)
    Swag.require(box.fltWrites == 1)
}

// Test: both value overloads in same scope
#test
{
    var box = RuntimeMultiValueBox{}
    box[0] = 42's32
    box[1] = 2.5'f32

    Swag.require(box.intVal == 42)
    Swag.require(box.floatVal == 3.5)
    Swag.require(box.intWrites == 1)
    Swag.require(box.fltWrites == 1)
}

// ============================================================================
// opIndex: const vs mutable overload dispatch
// ============================================================================

struct RuntimeConstMutBox
{
    data:     [2] s32
    mutReads: s32
}

impl RuntimeConstMutBox
{
    #[Swag.NoInline]
    mtd opIndexPtr(index: s32)->*s32
    {
        .mutReads += 1
        return &.data[index]
    }

    #[Swag.NoInline]
    mtd const opIndexPtr(index: s32)->const *s32
    {
        return &.data[index]
    }
}

// Test: mutable receiver calls mutable overload
#test
{
    var box = RuntimeConstMutBox{data: [7, 8]}
    let v   = box[0]

    Swag.require(v == 7)
    Swag.require(box.mutReads == 1)
}

// Test: const receiver calls const overload
#test
{
    const box = RuntimeConstMutBox{data: [7, 8]}
    let v = box[1]

    Swag.require(v == 8)
}

#test
{
    var box = RuntimeConstMutBox{data: [1, 2]}
    box[0] = 100
    Swag.require(box.data[0] == 100)
    Swag.require(box.mutReads == 1)
}
