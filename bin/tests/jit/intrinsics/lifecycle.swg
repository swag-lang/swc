#global fileprivate
using Swag

var DropCount: u32 = 0
var DropTrace: s64 = 0
var PostCopyCount: u32 = 0
var PostMoveCount: u32 = 0

func resetLifecycleHooks()
{
    DropCount = 0
    DropTrace = 0
    PostCopyCount = 0
    PostMoveCount = 0
}

func helperFree(buffer: [*] void, size: u64, allocator: IAllocator = null)
{
    if !buffer do
        return

    var req: AllocatorRequest
    req.mode = .Free
    req.size = size
    req.address = buffer

    let talloc = allocator orelse @getcontext().allocator
    talloc.req(&req)
}

func helperRealloc(buffer: [*] void, newSize: u64, oldSize: u64, allocator: IAllocator = null)->[*] void
{
    var req: AllocatorRequest
    req.mode = .Realloc
    req.address = buffer
    req.size = newSize
    req.oldSize = oldSize

    let talloc = allocator orelse @getcontext().allocator
    talloc.req(&req)
    return req.address
}

func memoryLikeFree(buffer: [*] void, size: u64, allocator: IAllocator = null, hint: string = null, loc = #callerlocation)
{
    if !buffer do
        return

    var req: AllocatorRequest
    req.callerLoc = loc
    req.mode = .Free
    req.size = size
    req.address = buffer
    req.hint = hint

    let talloc = allocator orelse @getcontext().allocator
    talloc.req(&req)
}

func memoryLikeRealloc(buffer: [*] void, newSize: u64, oldSize: u64, allocator: IAllocator = null, alignment: u16 = 0, hint: string = null, loc = #callerlocation)->[*] void
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint = hint
    req.mode = .Realloc
    req.address = buffer
    req.size = newSize
    req.oldSize = oldSize
    req.alignment = alignment

    let talloc = allocator orelse @getcontext().allocator
    talloc.req(&req)
    return req.address
}

struct IntrinsicInfo
{
    first: s32
    second: s32
    third: s32
    drops: u32
    dropTrace: s64
    postCopy: u32
    postMove: u32
}

struct InitInfo
{
    scalarDefault: s32
    scalarExplicitScaled: s32
    arrayDefaultTrace: s32
    arrayExplicitTrace: s32
    structDefaultTrace: s32
    structExplicitTrace: s32
    structArrayCountTrace: s32
    structArrayWholeTrace: s32
}

struct InitRgb
{
    r: s32 = 1
    g: s32 = 2
    b: s32 = 3
}

struct Tracked
{
    value: s32 = 5
}

impl Tracked
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(s64) .value
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
        .value += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .value += 20
    }
}

struct EmbeddedTracked
{
    inner: Tracked
}

struct EmbeddedTrackedArray
{
    inner: [2] Tracked
}

struct EmbeddedTrackedWithOps
{
    inner: Tracked
}

struct ResizeTracked
{
    value: s32
}

struct DropOnlyTracked
{
    value: s32
}

impl DropOnlyTracked
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(s64) .value
    }
}

struct AutoDropPair
{
    first: DropOnlyTracked
    second: DropOnlyTracked
}

struct AutoDropNested
{
    head: DropOnlyTracked
    pairs: [2] AutoDropPair
    tail: DropOnlyTracked
}

struct ResizeBuffer
{
    buffer: [*] ResizeTracked
    count: u64
}

impl ResizeBuffer
{
    mtd resize(newCount: u64)
    {
        if newCount == .count do
            return
        if newCount > .count do
            @init(.buffer + .count, newCount - .count)
        else do
            @drop(.buffer + newCount, .count - newCount)
        .count = newCount
    }
}

struct RemoveBuffer
{
    buffer: [*] DropOnlyTracked
    count: u64
}

impl RemoveBuffer
{
    mtd removeAt(index: u64)
    {
        .count -= 1
        if index == .count do
            @drop(.buffer + .count)
        else do
            .buffer[index] = #moveraw .buffer[.count]
    }
}

struct OwnedDropBuffer
{
    allocator: IAllocator
    buffer: [*] DropOnlyTracked
    count: u64
    capacity: u64
}

impl OwnedDropBuffer
{
    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)

        var req: AllocatorRequest
        req.mode = .Free
        req.size = .capacity * #sizeof(DropOnlyTracked)
        req.address = .buffer
        .allocator.req(&req)
        .buffer = null
    }
}

struct ReallocDropBuffer
{
    allocator: IAllocator
    buffer: [*] DropOnlyTracked
    count: u64
    capacity: u64
}

impl ReallocDropBuffer
{
    mtd opDrop()
    {
        .free()
    }

    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return

        var req: AllocatorRequest
        req.mode = .Realloc
        req.size = newCapacity * #sizeof(DropOnlyTracked)
        req.oldSize = .capacity * #sizeof(DropOnlyTracked)
        req.address = .buffer
        .allocator.req(&req)
        .buffer = cast([*] DropOnlyTracked) req.address
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] DropOnlyTracked
    {
        .reserve(.count + num)
        .count += num
        return .buffer + .count - num
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)

        var req: AllocatorRequest
        req.mode = .Free
        req.size = .capacity * #sizeof(DropOnlyTracked)
        req.address = .buffer
        .allocator.req(&req)
        .buffer = null
    }
}

struct(T) GenericOwnedBuffer
{
    allocator: IAllocator
    buffer: [*] T
    count: u64
    capacity: u64
}

impl GenericOwnedBuffer
{
    mtd opDrop()
    {
        .free()
    }

    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return

        var req: AllocatorRequest
        req.mode = .Realloc
        req.size = newCapacity * #sizeof(T)
        req.oldSize = .capacity * #sizeof(T)
        req.address = .buffer
        .allocator.req(&req)
        .buffer = cast([*] T) req.address
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] T
    {
        .reserve(.count + num)
        .count += num
        return .buffer + .count - num
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)

        var req: AllocatorRequest
        req.mode = .Free
        req.size = .capacity * #sizeof(T)
        req.address = .buffer
        .allocator.req(&req)
        .buffer = null
    }
}

struct(T) LazyAllocatorGenericBuffer
{
    allocator: IAllocator
    buffer: [*] T
    count: u64
    capacity: u64
}

impl LazyAllocatorGenericBuffer
{
    mtd opDrop()
    {
        .free()
    }

    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return
        if .allocator == null do
            .allocator = @getcontext().allocator

        var req: AllocatorRequest
        req.mode = .Realloc
        req.size = newCapacity * #sizeof(T)
        req.oldSize = .capacity * #sizeof(T)
        req.address = .buffer
        .allocator.req(&req)
        .buffer = cast([*] T) req.address
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] T
    {
        .reserve(.count + num)
        .count += num
        return .buffer + .count - num
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)

        var req: AllocatorRequest
        req.mode = .Free
        req.size = .capacity * #sizeof(T)
        req.address = .buffer
        .allocator.req(&req)
        .buffer = null
    }
}

struct(T) HelperAllocatorGenericBuffer
{
    allocator: IAllocator
    buffer: [*] T
    count: u64
    capacity: u64
}

impl HelperAllocatorGenericBuffer
{
    mtd opDrop()
    {
        .free()
    }

    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return
        if .allocator == null do
            .allocator = @getcontext().allocator

        .buffer = cast([*] T) helperRealloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator)
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] T
    {
        .reserve(.count + num)
        .count += num
        return .buffer + .count - num
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)
        helperFree(.buffer, .capacity * #sizeof(T), .allocator)
        .buffer = null
    }
}

struct(T) MemoryAllocatorGenericBuffer
{
    allocator: IAllocator
    buffer: [*] T
    count: u64
    capacity: u64
}

impl MemoryAllocatorGenericBuffer
{
    mtd opDrop()
    {
        .free()
    }

    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return
        if .allocator == null do
            .allocator = @getcontext().allocator

        .buffer = cast([*] T) memoryLikeRealloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator)
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] T
    {
        .reserve(.count + num)
        .count += num
        return .buffer + .count - num
    }

    mtd remove(index, num: u64)
    {
        if !num do
            return

        let shiftCount = .count - (index + num)
        for i in shiftCount do
            .buffer[index + i] = #moveraw .buffer[index + num + i]

        let droppedTail = num - shiftCount
        if droppedTail do
            @drop(.buffer + .count - droppedTail, droppedTail)

        .count -= num
    }

    mtd clear()
    {
        if !.count do
            return
        for .count do
            @drop(.buffer + @index)
        .count = 0
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)
        memoryLikeFree(.buffer, .capacity * #sizeof(T), .allocator)
        .buffer = null
        .count, .capacity = 0
    }
}

struct(T) PostCopyAllocatorGenericBuffer
{
    allocator: IAllocator
    buffer: [*] T
    count: u64
    capacity: u64
}

impl PostCopyAllocatorGenericBuffer
{
    mtd opDrop()
    {
        .free()
    }

    mtd opPostCopy()
    {
    }

    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return
        if .allocator == null do
            .allocator = @getcontext().allocator

        .buffer = cast([*] T) helperRealloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator)
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] T
    {
        .reserve(.count + num)
        .count += num
        return .buffer + .count - num
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)
        helperFree(.buffer, .capacity * #sizeof(T), .allocator)
        .buffer = null
    }
}

impl EmbeddedTrackedWithOps
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + 90
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
        .inner.value += 100
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .inner.value += 200
    }
}

struct ReceiverLifecycleTracked
{
    value: s32 = 3
}

impl ReceiverLifecycleTracked
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(s64) .value
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
        .value += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .value += 20
    }

    mtd reset()
    {
        @init(me, 1)
    }

    mtd touchPostCopy()
    {
        @postcopy(me, 1)
    }

    mtd touchPostMove()
    {
        @postmove(me, 1)
    }

    mtd touchDrop()
    {
        @drop(me, 1)
    }
}

func intrinsicSingleInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var a = Tracked{1}
    var b = Tracked{2}
    @postcopy(a)
    @postmove(b)
    @drop(a)
    return {a.value, b.value, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicArrayWholeInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var arr: [2] Tracked = [Tracked{3}, Tracked{4}]
    @postcopy(arr)
    @drop(arr)
    return {arr[0].value, arr[1].value, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicArrayCountInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var arr: [3] Tracked = [Tracked{1}, Tracked{2}, Tracked{3}]
    var count: u64 = 2
    @postmove(&arr[0], count)
    @drop(&arr[0], count)
    return {arr[0].value, arr[1].value, arr[2].value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicEmbeddedInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var a = EmbeddedTracked{Tracked{1}}
    var b = EmbeddedTrackedWithOps{Tracked{2}}
    var c = EmbeddedTrackedArray{[Tracked{3}, Tracked{4}]}
    @postcopy(a)
    @postmove(b)
    @drop(c)
    return {a.inner.value, b.inner.value, c.inner[1].value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicEmbeddedOuterCopyDropInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var a = EmbeddedTrackedWithOps{Tracked{7}}
    @postcopy(a)
    @drop(a)
    return {a.inner.value, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicInitInfo()->InitInfo
{
    var x = 666
    @init(x)

    var y = 666'f32
    @init(y)(3.14)

    var arr = [1, 2]
    @init(&arr, 2)
    let arrDefaultTrace = arr[0] * 10 + arr[1]

    @init(&arr, 2)(555)
    let arrExplicitTrace = arr[0] * 1000 + arr[1]

    var rgb = InitRgb{10, 20, 30}
    @init(rgb)
    let rgbDefaultTrace = rgb.r * 100 + rgb.g * 10 + rgb.b

    @init(rgb)(5, 6, 7)
    let rgbExplicitTrace = rgb.r * 100 + rgb.g * 10 + rgb.b

    var rgbArr: [4] InitRgb
    @init(&rgbArr, 4)(5, 6, 7)
    let rgbArrayCountTrace = rgbArr[3].r * 100 + rgbArr[3].g * 10 + rgbArr[3].b

    @init(rgbArr)(50, 60, 70)
    let rgbArrayWholeTrace = rgbArr[3].r * 10000 + rgbArr[3].g * 100 + rgbArr[3].b

    return {x, cast(s32) (y * 100), arrDefaultTrace, arrExplicitTrace, rgbDefaultTrace, rgbExplicitTrace, rgbArrayCountTrace, rgbArrayWholeTrace}
}

func intrinsicDropThenInitArrayInfo()->s32
{
    var rgb: [4] InitRgb
    @drop(&rgb, 4)
    @init(&rgb, 4)(5, 6, 7)
    return rgb[3].r * 100 + rgb[3].g * 10 + rgb[3].b
}

func intrinsicAutoDropPairInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    {
        var value = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}
        first = value.first.value
    }

    return {first, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropNestedInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    var last: s32 = 0
    {
        var value = AutoDropNested{DropOnlyTracked{1}, [AutoDropPair{DropOnlyTracked{2}, DropOnlyTracked{3}}, AutoDropPair{DropOnlyTracked{4}, DropOnlyTracked{5}}], DropOnlyTracked{6}}
        first = value.head.value
        last = value.tail.value
    }

    return {first, last, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropStructArrayInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    var last: s32 = 0
    {
        var values: [2] AutoDropPair = [AutoDropPair{DropOnlyTracked{7}, DropOnlyTracked{8}}, AutoDropPair{DropOnlyTracked{9}, DropOnlyTracked{10}}]
        first = values[0].first.value
        last = values[1].second.value
    }

    return {first, last, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicInitRuntimeCountScalarInfo()->s32
{
    var values: [4] s32 = [9, 8, 7, 6]
    var start: u64 = 1
    var count: u64 = 2
    @init(cast([*] s32) &values[0] + start, count)
    return values[0] * 1000 + values[1] * 100 + values[2] * 10 + values[3]
}

func intrinsicInitRuntimeCountStructInfo()->s32
{
    var values: [4] InitRgb = [InitRgb{9, 9, 9}, InitRgb{8, 8, 8}, InitRgb{7, 7, 7}, InitRgb{6, 6, 6}]
    var start: u64 = 1
    var count: u64 = 2
    @init(cast([*] InitRgb) &values[0] + start, count)
    return values[0].r * 1000 + values[1].r * 100 + values[2].r * 10 + values[3].r
}

func intrinsicFieldPointerResizeRuntimeInitInfo()->s32
{
    var storage: [4] ResizeTracked = [ResizeTracked{9}, ResizeTracked{8}, ResizeTracked{7}, ResizeTracked{6}]
    var values = ResizeBuffer{cast([*] ResizeTracked) &storage[0], 1}
    values.resize(3)
    return storage[0].value * 1000 + storage[1].value * 100 + storage[2].value * 10 + storage[3].value
}

func intrinsicFieldPointerResizeRuntimeDropIgnoredInfo()->s32
{
    var storage: [4] ResizeTracked = [ResizeTracked{9}, ResizeTracked{8}, ResizeTracked{7}, ResizeTracked{6}]
    var values = ResizeBuffer{cast([*] ResizeTracked) &storage[0], 3}
    values.resize(1)
    return storage[0].value * 1000 + storage[1].value * 100 + storage[2].value * 10 + cast(s32) values.count
}

func intrinsicRemoveAtDropOnlyInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var storage: [3] DropOnlyTracked = [DropOnlyTracked{1}, DropOnlyTracked{2}, DropOnlyTracked{3}]
    var values = RemoveBuffer{cast([*] DropOnlyTracked) &storage[0], 3}
    values.removeAt(1)
    return {storage[0].value, storage[1].value, cast(s32) values.count, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicHeapRemoveAtDropOnlyInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)
    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 3 * #sizeof(DropOnlyTracked)
    itf.req(&req)

    let ptr = cast([*] DropOnlyTracked) req.address
    @init(ptr, 3)
    for i in 3 do
        ptr[i].value = cast(s32) (i + 1)

    ptr[1] = #moveraw ptr[2]
    let first = ptr[0].value
    let second = ptr[1].value
    @drop(ptr, 2)
    req.mode = .Free
    itf.req(&req)
    return {first, second, 2, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicOwnedBufferFreeInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)
    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 3 * #sizeof(DropOnlyTracked)
    itf.req(&req)

    var values = OwnedDropBuffer{itf, cast([*] DropOnlyTracked) req.address, 3, 3}
    for i in 3 do
        values.buffer[i].value = cast(s32) (i + 1)

    values.free()
    return {0, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicMemoryAllocatorGenericBufferFreeInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    {
        var values: MemoryAllocatorGenericBuffer'DropOnlyTracked
        let ptr = values.emplaceAddress(3)
        for i in 3 do
            ptr[i].value = cast(s32) (i + 1)
        values.clear()
        values.free()
    }

    return {0, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicMemoryAllocatorGenericBufferRemoveRangeInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32
    var second: s32
    var third: s32

    {
        var values: MemoryAllocatorGenericBuffer'DropOnlyTracked
        let ptr = values.emplaceAddress(5)
        for i in 5 do
            ptr[i].value = cast(s32) (i + 1)

        values.remove(1, 3)
        first = values.buffer[0].value
        second = values.buffer[1].value
        third = cast(s32) values.count
        values.clear()
        values.free()
    }

    return {first, second, third, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicReallocOwnedBufferAutoDropInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    {
        var alloc: SystemAllocator
        var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)
        var values = ReallocDropBuffer{itf, null, 0, 0}
        let ptr = values.emplaceAddress(3)
        for i in 3 do
            ptr[i].value = cast(s32) (i + 1)
    }

    return {0, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicGenericOwnedBufferAutoDropInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    {
        var alloc: SystemAllocator
        var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)
        var values = GenericOwnedBuffer'DropOnlyTracked{itf, null, 0, 0}
        let ptr = values.emplaceAddress(3)
        for i in 3 do
            ptr[i].value = cast(s32) (i + 1)
    }

    return {0, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicGenericOwnedBufferContextAllocatorAutoDropInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    {
        var values = GenericOwnedBuffer'DropOnlyTracked{@getcontext().allocator, null, 0, 0}
        let ptr = values.emplaceAddress(3)
        for i in 3 do
            ptr[i].value = cast(s32) (i + 1)
    }

    return {0, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicLazyAllocatorGenericBufferAutoDropInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    {
        var values: LazyAllocatorGenericBuffer'DropOnlyTracked
        let ptr = values.emplaceAddress(3)
        for i in 3 do
            ptr[i].value = cast(s32) (i + 1)
    }

    return {0, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicHelperAllocatorGenericBufferAutoDropInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    {
        var values: HelperAllocatorGenericBuffer'DropOnlyTracked
        let ptr = values.emplaceAddress(3)
        for i in 3 do
            ptr[i].value = cast(s32) (i + 1)
    }

    return {0, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicPostCopyAllocatorGenericBufferAutoDropInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    {
        var values: PostCopyAllocatorGenericBuffer'DropOnlyTracked
        let ptr = values.emplaceAddress(3)
        for i in 3 do
            ptr[i].value = cast(s32) (i + 1)
    }

    return {0, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicPostCopyAllocatorGenericBufferExplicitOpDropInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    {
        var values: PostCopyAllocatorGenericBuffer'DropOnlyTracked
        let ptr = values.emplaceAddress(3)
        for i in 3 do
            ptr[i].value = cast(s32) (i + 1)
        values.opDrop()
    }

    return {0, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicReallocOwnedBufferFreeInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)
    var values = ReallocDropBuffer{itf, null, 0, 0}
    let ptr = values.emplaceAddress(3)
    for i in 3 do
        ptr[i].value = cast(s32) (i + 1)

    values.free()
    return {0, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicReceiverLifecycleInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var value = ReceiverLifecycleTracked{7}
    value.touchPostCopy()
    value.touchPostMove()
    value.touchDrop()
    value.reset()
    return {value.value, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

#test
{
    let v = intrinsicSingleInfo()
    @assert(v.first == 11)
    @assert(v.second == 22)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 11)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 1)
}

#test
{
    let v = intrinsicArrayWholeInfo()
    @assert(v.first == 13)
    @assert(v.second == 14)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 1314)
    @assert(v.postCopy == 2)
    @assert(v.postMove == 0)
}

#test
{
    let v = intrinsicArrayCountInfo()
    @assert(v.first == 21)
    @assert(v.second == 22)
    @assert(v.third == 3)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 2122)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 2)
}

#test
{
    let v = intrinsicEmbeddedInfo()
    @assert(v.first == 11)
    @assert(v.second == 222)
    @assert(v.third == 4)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 304)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 2)
}

#test
{
    let v = intrinsicEmbeddedOuterCopyDropInfo()
    @assert(v.first == 117)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 9117)
    @assert(v.postCopy == 2)
    @assert(v.postMove == 0)
}

#test
{
    let v = intrinsicInitInfo()
    @assert(v.scalarDefault == 0)
    @assert(v.scalarExplicitScaled == 314)
    @assert(v.arrayDefaultTrace == 0)
    @assert(v.arrayExplicitTrace == 555555)
    @assert(v.structDefaultTrace == 123)
    @assert(v.structExplicitTrace == 567)
    @assert(v.structArrayCountTrace == 567)
    @assert(v.structArrayWholeTrace == 506070)
}

#test
{
    let v = intrinsicDropThenInitArrayInfo()
    @assert(v == 567)
}

#test
{
    let v = intrinsicAutoDropPairInfo()
    @assert(v.first == 1)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 201)
}

#test
{
    let v = intrinsicAutoDropNestedInfo()
    @assert(v.first == 1)
    @assert(v.second == 6)
    @assert(v.drops == 6)
    @assert(v.dropTrace == 60302050401)
}

#test
{
    let v = intrinsicAutoDropStructArrayInfo()
    @assert(v.first == 7)
    @assert(v.second == 10)
    @assert(v.drops == 4)
    @assert(v.dropTrace == 8071009)
}

#test
{
    let scalarTrace = intrinsicInitRuntimeCountScalarInfo()
    @assert(scalarTrace == 9006)

    let structTrace = intrinsicInitRuntimeCountStructInfo()
    @assert(structTrace == 9116)
}

#test
{
    let trace = intrinsicFieldPointerResizeRuntimeInitInfo()
    @assert(trace == 9006)
}

#test
{
    let trace = intrinsicFieldPointerResizeRuntimeDropIgnoredInfo()
    @assert(trace == 9871)
}

#test
{
    let v = intrinsicRemoveAtDropOnlyInfo()
    @assert(v.first == 1)
    @assert(v.second == 3)
    @assert(v.third == 2)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 2)
}

#test
{
    let v = intrinsicHeapRemoveAtDropOnlyInfo()
    @assert(v.first == 1)
    @assert(v.second == 3)
    @assert(v.third == 2)
    @assert(v.drops == 3)
    @assert(v.dropTrace == 20103)
}

#test
{
    let v = intrinsicOwnedBufferFreeInfo()
    @assert(v.drops == 3)
    @assert(v.dropTrace == 10203)
}

#test
{
    let v = intrinsicMemoryAllocatorGenericBufferFreeInfo()
    @assert(v.drops == 3)
    @assert(v.dropTrace == 10203)
}

#test
{
    let v = intrinsicMemoryAllocatorGenericBufferRemoveRangeInfo()
    @assert(v.first == 1)
    @assert(v.second == 5)
    @assert(v.third == 2)
    @assert(v.drops == 5)
}

#test
{
    let v = intrinsicReallocOwnedBufferFreeInfo()
    @assert(v.drops == 3)
    @assert(v.dropTrace == 10203)
}

#test
{
    let v = intrinsicReallocOwnedBufferAutoDropInfo()
    @assert(v.drops == 3)
    @assert(v.dropTrace == 10203)
}

#test
{
    let v = intrinsicGenericOwnedBufferAutoDropInfo()
    @assert(v.drops == 3)
    @assert(v.dropTrace == 10203)
}

#test
{
    let v = intrinsicGenericOwnedBufferContextAllocatorAutoDropInfo()
    @assert(v.drops == 3)
    @assert(v.dropTrace == 10203)
}

#test
{
    let v = intrinsicLazyAllocatorGenericBufferAutoDropInfo()
    @assert(v.drops == 3)
    @assert(v.dropTrace == 10203)
}

#test
{
    let v = intrinsicHelperAllocatorGenericBufferAutoDropInfo()
    @assert(v.drops == 3)
    @assert(v.dropTrace == 10203)
}

#test
{
    let v = intrinsicPostCopyAllocatorGenericBufferAutoDropInfo()
    @assert(v.drops == 3)
    @assert(v.dropTrace == 10203)
}

#test
{
    let v = intrinsicPostCopyAllocatorGenericBufferExplicitOpDropInfo()
    @assert(v.drops == 3)
    @assert(v.dropTrace == 10203)
}

#test
{
    let v = intrinsicReceiverLifecycleInfo()
    @assert(v.first == 3)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 37)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 1)
}
