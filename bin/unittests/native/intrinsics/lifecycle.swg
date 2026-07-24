#global private
// This file asserts the RAW '@drop'/'@postcopy'/'@postmove'/'@init' mechanics,
// including reading storage after '@drop': lifecycle safety (use-after-move check +
// poisoning) is disabled for the whole file.
#global #[Swag.Safety(.Lifecycle, false), Swag.Sanity(.Lifecycle, false)]
using Swag

var DropCount:        u32 = 0
var DropTrace:        s64 = 0
var DropCompactTrace: s64 = 0
var PostCopyCount:    u32 = 0
var PostMoveCount:    u32 = 0

func resetLifecycleHooks()
{
    DropCount        = 0
    DropTrace        = 0
    DropCompactTrace = 0
    PostCopyCount    = 0
    PostMoveCount    = 0
}

func helperFree(buffer: #null [*] void, size: u64, allocator: #null IAllocator = null)
{
    if !buffer do
        return

    var req: AllocatorRequest
    req.size    = size
    req.address = buffer

    let talloc = notnull (allocator orelse @getcontext().allocator)
    talloc.free(&req)
}

func helperRealloc(buffer: #null [*] void, newSize: u64, oldSize: u64, allocator: #null IAllocator = null)->#null [*] void
{
    var req: AllocatorRequest
    req.address = buffer
    req.size    = newSize
    req.oldSize = oldSize

    let talloc = notnull (allocator orelse @getcontext().allocator)
    talloc.realloc(&req)
    return req.address
}

func memoryLikeFree(buffer: #null [*] void, size: u64, allocator: #null IAllocator = null, hint: #null string = null, loc = #callerlocation)
{
    if !buffer do
        return

    var req: AllocatorRequest
    req.callerLoc = loc
    req.size      = size
    req.address   = buffer
    req.hint      = hint

    let talloc = notnull (allocator orelse @getcontext().allocator)
    talloc.free(&req)
}

func memoryLikeRealloc(buffer: #null [*] void, newSize: u64, oldSize: u64, allocator: #null IAllocator = null, alignment: u16 = 0, hint: #null string = null, loc = #callerlocation)->#null [*] void
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.address   = buffer
    req.size      = newSize
    req.oldSize   = oldSize
    req.alignment = alignment

    let talloc = notnull (allocator orelse @getcontext().allocator)
    talloc.realloc(&req)
    return req.address
}

struct IntrinsicInfo
{
    first:     s32
    second:    s32
    third:     s32
    drops:     u32
    dropTrace: s64
    postCopy:  u32
    postMove:  u32
}

struct InitInfo
{
    scalarDefault:         s32
    scalarExplicitScaled:  s32
    arrayDefaultTrace:     s32
    arrayExplicitTrace:    s32
    structDefaultTrace:    s32
    structExplicitTrace:   s32
    structArrayCountTrace: s32
    structArrayWholeTrace: s32
}

struct InitRgb
{
    r: s32 = 1
    g: s32 = 2
    b: s32 = 3
}

enum IntrinsicStrictEnum: u32
{
    Zero = 0,
    A    = 1,
    B    = 2,
}

#[Swag.Strict]
alias IntrinsicStrictEnumAlias = IntrinsicStrictEnum

#[Swag.Strict]
alias IntrinsicStrictIntAlias = s32

#[Swag.Strict]
alias IntrinsicStrictFloatAlias = f32

#[Swag.Strict]
alias IntrinsicStrictS32Ptr = *s32

#[Swag.Strict]
alias IntrinsicStrictStringAlias = string

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
        .value        += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .value        += 20
    }
}

#[Swag.Strict]
alias LifecycleStrictTrackedPtr = *Tracked

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
    first:  DropOnlyTracked
    second: DropOnlyTracked
}

struct AutoDropNested
{
    head:  DropOnlyTracked
    pairs: [2] AutoDropPair
    tail:  DropOnlyTracked
}

struct AutoDropBranch
{
    head: DropOnlyTracked
    pair: AutoDropPair
}

struct CompactDropTracked
{
    value: s32
}

impl CompactDropTracked
{
    mtd opDrop()
    {
        DropCount        += 1
        DropCompactTrace = DropCompactTrace * 10 + cast(s64) .value
    }
}

struct AutoCompactPair
{
    first:  CompactDropTracked
    second: CompactDropTracked
}

struct AutoCompactBranch
{
    head: CompactDropTracked
    pair: AutoCompactPair
}

struct IntrinsicLifecycleErr
{
    using base: Swag.BaseError
    code:       s32 = 0
}

struct ResizeBuffer
{
    buffer: [*] ResizeTracked
    count:  u64
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
    count:  u64
}

impl RemoveBuffer
{
    mtd removeAt(index: u64)
    {
        .count -= 1
        if index == .count
        {
            @drop(.buffer + .count)
        }
        else
        {
            @drop(.buffer + index)
            .buffer[index] = #relocate .buffer[.count]
        }
    }
}

struct OwnedDropBuffer
{
    allocator: #null IAllocator
    buffer:    #null [*] DropOnlyTracked
    count:     u64
    capacity:  u64
}

impl OwnedDropBuffer
{
    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)

        var req: AllocatorRequest
        req.size    = .capacity * #sizeof(DropOnlyTracked)
        req.address = .buffer
        let allocItf = notnull .allocator
        allocItf.free(&req)
        .buffer = null
    }
}

struct ReallocDropBuffer
{
    allocator: #null IAllocator
    buffer:    #null [*] DropOnlyTracked
    count:     u64
    capacity:  u64
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
        req.size    = newCapacity * #sizeof(DropOnlyTracked)
        req.oldSize = .capacity * #sizeof(DropOnlyTracked)
        req.address = .buffer
        let allocItf = notnull .allocator
        allocItf.realloc(&req)
        .buffer   = cast(#null [*] DropOnlyTracked) req.address
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] DropOnlyTracked
    {
        .reserve(.count + num)
        .count += num
        let buffer = notnull .buffer
        return buffer + .count - num
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)

        var req: AllocatorRequest
        req.size    = .capacity * #sizeof(DropOnlyTracked)
        req.address = .buffer
        let allocItf = notnull .allocator
        allocItf.free(&req)
        .buffer = null
    }
}

struct(T) GenericOwnedBuffer
{
    allocator: #null IAllocator
    buffer:    #null [*] T
    count:     u64
    capacity:  u64
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
        req.size    = newCapacity * #sizeof(T)
        req.oldSize = .capacity * #sizeof(T)
        req.address = .buffer
        let allocItf = notnull .allocator
        allocItf.realloc(&req)
        .buffer   = cast(#null [*] T) req.address
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] T
    {
        .reserve(.count + num)
        .count += num
        let buffer = notnull .buffer
        return buffer + .count - num
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)

        var req: AllocatorRequest
        req.size    = .capacity * #sizeof(T)
        req.address = .buffer
        let allocItf = notnull .allocator
        allocItf.free(&req)
        .buffer = null
    }
}

struct(T) LazyAllocatorGenericBuffer
{
    allocator: #null IAllocator
    buffer:    #null [*] T
    count:     u64
    capacity:  u64
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
        req.size    = newCapacity * #sizeof(T)
        req.oldSize = .capacity * #sizeof(T)
        req.address = .buffer
        let allocItf = notnull .allocator
        allocItf.realloc(&req)
        .buffer   = cast(#null [*] T) req.address
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] T
    {
        .reserve(.count + num)
        .count += num
        let buffer = notnull .buffer
        return buffer + .count - num
    }

    mtd free()
    {
        if !.buffer do
            return

        @drop(.buffer, .count)

        var req: AllocatorRequest
        req.size    = .capacity * #sizeof(T)
        req.address = .buffer
        let allocItf = notnull .allocator
        allocItf.free(&req)
        .buffer = null
    }
}

struct(T) HelperAllocatorGenericBuffer
{
    allocator: #null IAllocator
    buffer:    #null [*] T
    count:     u64
    capacity:  u64
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

        .buffer   = cast(#null [*] T) helperRealloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator)
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] T
    {
        .reserve(.count + num)
        .count += num
        let buffer = notnull .buffer
        return buffer + .count - num
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
    allocator: #null IAllocator
    buffer:    #null [*] T
    count:     u64
    capacity:  u64
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

        .buffer   = cast(#null [*] T) memoryLikeRealloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator)
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] T
    {
        .reserve(.count + num)
        .count += num
        let buffer = notnull .buffer
        return buffer + .count - num
    }

    mtd remove(index, num: u64)
    {
        if !num do
            return

        // Drop the removed elements, then relocate the survivors into the freed slots.
        let buffer = notnull .buffer
        @drop(buffer + index, num)
        let shiftCount = .count - (index + num)
        for i in shiftCount do
            buffer[index + i] = #relocate buffer[index + num + i]

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
        .buffer           = null
        .count, .capacity = 0
    }
}

struct(T) PostCopyAllocatorGenericBuffer
{
    allocator: #null IAllocator
    buffer:    #null [*] T
    count:     u64
    capacity:  u64
}

impl PostCopyAllocatorGenericBuffer
{
    mtd opDrop()
    {
        .free()
    }

    mtd opPostCopy() {}

    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return
        if .allocator == null do
            .allocator = @getcontext().allocator

        .buffer   = cast(#null [*] T) helperRealloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator)
        .capacity = newCapacity
    }

    mtd emplaceAddress(num: u64 = 1)->[*] T
    {
        .reserve(.count + num)
        .count += num
        let buffer = notnull .buffer
        return buffer + .count - num
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
        .inner.value  += 100
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .inner.value  += 200
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
        .value        += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .value        += 20
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
    var arr:   [3] Tracked = [Tracked{1}, Tracked{2}, Tracked{3}]
    var count: u64 = 2
    @postmove(&arr[0], count)
    @drop(&arr[0], count)
    return {arr[0].value, arr[1].value, arr[2].value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicStrictAliasPointerCountInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var arr: [2] Tracked = [Tracked{5}, Tracked{6}]
    let ptr = cast(LifecycleStrictTrackedPtr) &arr[0]
    @postmove(ptr, 2)
    @drop(ptr, 2)
    return {arr[0].value, arr[1].value, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
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
    var last:  s32 = 0
    {
        var value = AutoDropNested{DropOnlyTracked{1}, [AutoDropPair{DropOnlyTracked{2}, DropOnlyTracked{3}}, AutoDropPair{DropOnlyTracked{4}, DropOnlyTracked{5}}], DropOnlyTracked{6}}
        first = value.head.value
        last  = value.tail.value
    }

    return {first, last, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropStructArrayInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    var last:  s32 = 0
    {
        var values: [2] AutoDropPair = [AutoDropPair{DropOnlyTracked{7}, DropOnlyTracked{8}}, AutoDropPair{DropOnlyTracked{9}, DropOnlyTracked{10}}]
        first = values[0].first.value
        last  = values[1].second.value
    }

    return {first, last, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropReturnInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first     = 0
        .second    = 0
        .third     = 0
        .drops     = 0
        .dropTrace = 0
        .postCopy  = 0
        .postMove  = 0
    }

    defer result.dropTrace = DropTrace
    defer result.drops = DropCount

    {
        var pair = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}
        result.first = pair.first.value

        {
            var nested = AutoDropNested{DropOnlyTracked{3}, [AutoDropPair{DropOnlyTracked{4}, DropOnlyTracked{5}}, AutoDropPair{DropOnlyTracked{6}, DropOnlyTracked{7}}], DropOnlyTracked{8}}
            result.second = nested.tail.value
            result.third  = nested.pairs[1].second.value
            return result
        }
    }
}

func intrinsicAutoDropErrorImpl() throw
{
    {
        var pair = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}

        {
            var nested = AutoDropNested{DropOnlyTracked{3}, [AutoDropPair{DropOnlyTracked{4}, DropOnlyTracked{5}}, AutoDropPair{DropOnlyTracked{6}, DropOnlyTracked{7}}], DropOnlyTracked{8}}
            if pair.first.value == 1 and nested.tail.value == 8 do
                throw IntrinsicLifecycleErr{code: 77}
        }
    }
}

func intrinsicAutoDropErrorInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first     = 0
        .second    = 0
        .third     = 0
        .drops     = 0
        .dropTrace = 0
        .postCopy  = 0
        .postMove  = 0
    }

    catch intrinsicAutoDropErrorImpl()
    if @err != null
    {
        let err = cast(IntrinsicLifecycleErr) @err
        result.first  = err.code
        result.second = 1
    }

    result.drops     = DropCount
    result.dropTrace = DropTrace
    return result
}

func intrinsicAutoDropDeferInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first     = 0
        .second    = 0
        .third     = 0
        .drops     = 0
        .dropTrace = 0
        .postCopy  = 0
        .postMove  = 0
    }

    {
        defer result.first = cast(s32) DropCount
        var pair = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}

        {
            defer result.second = cast(s32) DropCount
            var nested = AutoDropNested{DropOnlyTracked{3}, [AutoDropPair{DropOnlyTracked{4}, DropOnlyTracked{5}}, AutoDropPair{DropOnlyTracked{6}, DropOnlyTracked{7}}], DropOnlyTracked{8}}
            result.third = nested.tail.value
        }
    }

    result.drops     = DropCount
    result.dropTrace = DropTrace
    return result
}

func intrinsicAutoDropContinueInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first:  s32 = 0
    var second: s32 = 0
    var third:  s32 = 0
    {
        var outer = DropOnlyTracked{9}
        for i in 2
        {
            var pair = AutoDropPair{DropOnlyTracked{cast(s32) (i * 2 + 1)}, DropOnlyTracked{cast(s32) (i * 2 + 2)}}
            first += pair.first.value
            if i == 0 do
                continue

            var branch = AutoDropBranch{DropOnlyTracked{5}, AutoDropPair{DropOnlyTracked{6}, DropOnlyTracked{7}}}
            second = branch.head.value
            third  = outer.value
        }
    }

    return {first, second, third, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropBreakScopeInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first:  s32 = 0
    var second: s32 = 0
    var third:  s32 = 0
    {
        var outer = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}
        #scope(Exit)
        {
            var scopeValue = AutoDropBranch{DropOnlyTracked{3}, AutoDropPair{DropOnlyTracked{4}, DropOnlyTracked{5}}}
            first = outer.first.value + scopeValue.head.value

            for i in 3
            {
                var current = AutoDropPair{DropOnlyTracked{6}, DropOnlyTracked{7}}
                second = current.second.value + cast(s32) i
                break to Exit
            }
        }

        third = outer.second.value
    }

    return {first, second, third, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropSwitchReturnInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first     = 0
        .second    = 0
        .third     = 0
        .drops     = 0
        .dropTrace = 0
        .postCopy  = 0
        .postMove  = 0
    }

    defer result.dropTrace = DropTrace
    defer result.drops = DropCount

    {
        var outer = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}
        switch 2
        {
        case 1:
            result.first = -1

        case 2:
            var active = AutoDropBranch{DropOnlyTracked{6}, AutoDropPair{DropOnlyTracked{7}, DropOnlyTracked{8}}}
            result.first  = outer.second.value
            result.second = active.head.value
            result.third  = active.pair.first.value
            return result

        default:
            result.third = -2
        }
    }

    return result
}

func intrinsicAutoDropCatchResumeImpl(code: s32) throw
{
    var branch = AutoCompactBranch{CompactDropTracked{3}, AutoCompactPair{CompactDropTracked{4}, CompactDropTracked{5}}}
    if branch.head.value == 3 do
        throw IntrinsicLifecycleErr{code: code}
}

func intrinsicAutoDropCatchResumeInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first:  s32 = 0
    var second: s32 = 0
    var third:  s32 = 0
    {
        var outer = AutoCompactPair{CompactDropTracked{8}, CompactDropTracked{9}}
        catch intrinsicAutoDropCatchResumeImpl(55)
        if @err != null
        {
            let err = cast(IntrinsicLifecycleErr) @err
            first  = err.code
            second = outer.second.value
            third  = 1
        }
    }

    return {first, second, third, DropCount, DropCompactTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropTryCatchLoopStep(base: s32)->s32 throw
{
    var branch = AutoCompactBranch{CompactDropTracked{base}, AutoCompactPair{CompactDropTracked{base + 1}, CompactDropTracked{base + 2}}}
    if base == 1 do
        throw IntrinsicLifecycleErr{code: 66}
    return branch.pair.first.value
}

func intrinsicAutoDropTryCatchLoopInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first:  s32 = 0
    var second: s32 = 0
    var third:  s32 = 0
    {
        var outer = CompactDropTracked{9}
        for i in 2
        {
            let base = cast(s32) (i * 3 + 1)
            let value: s32 = trycatch intrinsicAutoDropTryCatchLoopStep(base)
            if value == 0
            {
                second += 1
                continue
            }

            first += value
            var pair = AutoCompactPair{CompactDropTracked{7}, CompactDropTracked{8}}
            third = pair.second.value + outer.value
        }
    }

    return {first, second, third, DropCount, DropCompactTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropSwitchFallthroughInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first     = 0
        .second    = 0
        .third     = 0
        .drops     = 0
        .dropTrace = 0
        .postCopy  = 0
        .postMove  = 0
    }

    defer result.dropTrace = DropCompactTrace
    defer result.drops = DropCount

    {
        var outer = AutoCompactPair{CompactDropTracked{6}, CompactDropTracked{7}}
        switch 1
        {
        case 1:
            {
                var firstCase = AutoCompactPair{CompactDropTracked{1}, CompactDropTracked{2}}
                result.first = firstCase.first.value
            }
            fallthrough

        case 2:
            {
                var active = AutoCompactBranch{CompactDropTracked{3}, AutoCompactPair{CompactDropTracked{4}, CompactDropTracked{5}}}
                result.second = active.head.value
                result.third  = outer.second.value
                return result
            }

        default:
            result.third = -1
        }
    }

    return result
}

func intrinsicAutoDropIfVarReturnInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first     = 0
        .second    = 0
        .third     = 0
        .drops     = 0
        .dropTrace = 0
        .postCopy  = 0
        .postMove  = 0
    }

    defer result.dropTrace = DropCompactTrace
    defer result.drops = DropCount

    {
        var outer = CompactDropTracked{1}
        if var flag = 1 where flag == 1
        {
            var branch = AutoCompactBranch{CompactDropTracked{2}, AutoCompactPair{CompactDropTracked{3}, CompactDropTracked{4}}}
            var inner = AutoCompactPair{CompactDropTracked{5}, CompactDropTracked{6}}
            result.first  = flag + outer.value
            result.second = branch.pair.first.value
            result.third  = inner.second.value
            return result
        }
    }

    result.third = -1
    return result
}

func intrinsicAutoDropIfVarElseInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first:  s32 = 0
    var second: s32 = 0
    var third:  s32 = 0
    {
        var outer = CompactDropTracked{9}
        if var flag = 1 where false
        {
            first = -1
        }
        else
        {
            var active = AutoCompactBranch{CompactDropTracked{1}, AutoCompactPair{CompactDropTracked{2}, CompactDropTracked{3}}}
            first  = flag + 5
            second = active.head.value
            third  = outer.value
        }
    }

    return {first, second, third, DropCount, DropCompactTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropWithVarReturnInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first     = 0
        .second    = 0
        .third     = 0
        .drops     = 0
        .dropTrace = 0
        .postCopy  = 0
        .postMove  = 0
    }

    defer result.dropTrace = DropCompactTrace
    defer result.drops = DropCount

    with var pair = AutoCompactPair{CompactDropTracked{7}, CompactDropTracked{8}}
    {
        var active = AutoCompactBranch{CompactDropTracked{4}, AutoCompactPair{CompactDropTracked{5}, CompactDropTracked{6}}}
        result.first  = pair.first.value
        result.second = active.head.value
        result.third  = pair.second.value
        return result
    }

    result.third = -1
    return result
}

func intrinsicAutoDropShadowInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first:  s32 = 0
    var second: s32 = 0
    var third:  s32 = 0
    {
        var value = CompactDropTracked{9}
        first = value.value

        {
            var value = AutoCompactBranch{CompactDropTracked{1}, AutoCompactPair{CompactDropTracked{2}, CompactDropTracked{3}}}
            second = value.pair.first.value
        }

        var pair = AutoCompactPair{CompactDropTracked{4}, CompactDropTracked{5}}
        third = pair.second.value
    }

    return {first, second, third, DropCount, DropCompactTrace, PostCopyCount, PostMoveCount}
}

func intrinsicInitRuntimeCountScalarInfo()->s32
{
    var values: [4] s32 = [9, 8, 7, 6]
    var start:  u64 = 1
    var count:  u64 = 2
    @init(cast([*] s32) &values[0] + start, count)
    return values[0] * 1000 + values[1] * 100 + values[2] * 10 + values[3]
}

func intrinsicInitRuntimeCountStructInfo()->s32
{
    var values: [4] InitRgb = [InitRgb{9, 9, 9}, InitRgb{8, 8, 8}, InitRgb{7, 7, 7}, InitRgb{6, 6, 6}]
    var start:  u64 = 1
    var count:  u64 = 2
    @init(cast([*] InitRgb) &values[0] + start, count)
    return values[0].r * 1000 + values[1].r * 100 + values[2].r * 10 + values[3].r
}

func intrinsicInitRuntimeCountClosureInfo()->s32
{
    var values: [3] #null func||()->s32
    values[0] = func()->s32 { return 4 }
    values[1] = func()->s32 { return 5 }
    values[2] = func()->s32 { return 6 }
    var start: u64 = 1
    var count: u64 = 2
    @init(cast([*] #null func||()->s32) &values[0] + start, count)
    let first = notnull values[0]
    return first() * 100 + cast(s32) (values[1] == null) * 10 + cast(s32) (values[2] == null)
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
    let itf = notnull @getcontext().allocator
    var req: AllocatorRequest
    req.size = 3 * #sizeof(DropOnlyTracked)
    itf.alloc(&req)

    let ptr = cast([*] DropOnlyTracked) notnull req.address
    @init(ptr, 3)
    for i in 3 do
        ptr[i].value = cast(s32) (i + 1)

    @drop(ptr + 1)
    ptr[1] = #relocate ptr[2]
    let first = ptr[0].value
    let second = ptr[1].value
    @drop(ptr, 2)
    itf.free(&req)
    return {first, second, 2, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicOwnedBufferFreeInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    let itf = notnull @getcontext().allocator
    var req: AllocatorRequest
    req.size = 3 * #sizeof(DropOnlyTracked)
    itf.alloc(&req)

    var values = OwnedDropBuffer{itf, cast(#null [*] DropOnlyTracked) req.address, 3, 3}
    let buffer = notnull values.buffer
    for i in 3 do
        buffer[i].value = cast(s32) (i + 1)

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

    var first:  s32
    var second: s32
    var third:  s32

    {
        var values: MemoryAllocatorGenericBuffer'DropOnlyTracked
        let ptr = values.emplaceAddress(5)
        for i in 5 do
            ptr[i].value = cast(s32) (i + 1)

        values.remove(1, 3)
        let buffer = notnull values.buffer
        first  = buffer[0].value
        second = buffer[1].value
        third  = cast(s32) values.count
        values.clear()
        values.free()
    }

    return {first, second, third, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicReallocOwnedBufferAutoDropInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    {
        let itf = notnull @getcontext().allocator
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
        let itf = notnull @getcontext().allocator
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

    let itf = notnull @getcontext().allocator
    var values = ReallocDropBuffer{itf, null, 0, 0}
    let ptr = values.emplaceAddress(3)
    for i in 3 do
        ptr[i].value = cast(s32) (i + 1)

    values.free()
    return {0, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicInitStrictEnumInfo()->bool
{
    var value: IntrinsicStrictEnumAlias
    @init(value)(cast(IntrinsicStrictEnumAlias) IntrinsicStrictEnum.B)

    var values: [3] IntrinsicStrictEnumAlias
    @init(&values, 3)(cast(IntrinsicStrictEnumAlias) IntrinsicStrictEnum.A)

    return value == cast(IntrinsicStrictEnumAlias) IntrinsicStrictEnum.B and values[0] == cast(IntrinsicStrictEnumAlias) IntrinsicStrictEnum.A and values[2] == cast(IntrinsicStrictEnumAlias) IntrinsicStrictEnum.A
}

func intrinsicInitStrictIntInfo()->bool
{
    var value: IntrinsicStrictIntAlias
    @init(value)(cast(IntrinsicStrictIntAlias) 42)

    var values: [3] IntrinsicStrictIntAlias
    @init(&values, 3)(cast(IntrinsicStrictIntAlias) 7)

    return value == cast(IntrinsicStrictIntAlias) 42 and values[0] == cast(IntrinsicStrictIntAlias) 7 and values[2] == cast(IntrinsicStrictIntAlias) 7
}

func intrinsicInitStrictFloatInfo()->bool
{
    var value: IntrinsicStrictFloatAlias
    @init(value)(cast(IntrinsicStrictFloatAlias) 1.5)

    var values: [3] IntrinsicStrictFloatAlias
    @init(&values, 3)(cast(IntrinsicStrictFloatAlias) 2.5)

    return value == cast(IntrinsicStrictFloatAlias) 1.5 and values[0] == cast(IntrinsicStrictFloatAlias) 2.5 and values[2] == cast(IntrinsicStrictFloatAlias) 2.5
}

func intrinsicInitStrictPointerInfo()->bool
{
    var first:  s32 = 42
    var second: s32 = 7

    var value: IntrinsicStrictS32Ptr = undefined
    @init(&value)(cast(IntrinsicStrictS32Ptr) &first)

    var values: [2] IntrinsicStrictS32Ptr = undefined
    @init(&values, 2)(cast(IntrinsicStrictS32Ptr) &second)

    return dref value == 42 and dref values[0] == 7 and dref values[1] == 7
}

func intrinsicInitStrictStringInfo()->bool
{
    var value: IntrinsicStrictStringAlias = undefined
    @init(&value)(cast(IntrinsicStrictStringAlias) "hello")

    var values: [2] IntrinsicStrictStringAlias = undefined
    @init(&values, 2)(cast(IntrinsicStrictStringAlias) "world")

    return cast(string) value == "hello" and cast(string) values[0] == "world" and cast(string) values[1] == "world"
}

func makeIntrinsicRunStrictIntArray()->[2] IntrinsicStrictIntAlias
{
    return [cast(IntrinsicStrictIntAlias) 11, cast(IntrinsicStrictIntAlias) 13]
}

func makeIntrinsicRunStrictFloatArray()->[2] IntrinsicStrictFloatAlias
{
    return [cast(IntrinsicStrictFloatAlias) 1.25, cast(IntrinsicStrictFloatAlias) 2.5]
}

const IntrinsicRunStrictInts: [2] IntrinsicStrictIntAlias     = #run makeIntrinsicRunStrictIntArray()
const IntrinsicRunStrictFloats: [2] IntrinsicStrictFloatAlias = #run makeIntrinsicRunStrictFloatArray()

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
    let v = intrinsicStrictAliasPointerCountInfo()
    @assert(v.first == 25)
    @assert(v.second == 26)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 2526)
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
    let v = intrinsicAutoDropReturnInfo()
    @assert(v.first == 1)
    @assert(v.second == 8)
    @assert(v.third == 7)
    @assert(v.drops == 8)
    @assert(v.dropTrace == 805040706030201)
}

#test
{
    let v = intrinsicAutoDropErrorInfo()
    @assert(v.first == 77)
    @assert(v.second == 1)
    @assert(v.drops == 8)
    @assert(v.dropTrace == 805040706030201)
}

#test
{
    let v = intrinsicAutoDropDeferInfo()
    @assert(v.first == 8)
    @assert(v.second == 6)
    @assert(v.third == 8)
    @assert(v.drops == 8)
    @assert(v.dropTrace == 805040706030201)
}

#test
{
    let v = intrinsicAutoDropContinueInfo()
    @assert(v.first == 4)
    @assert(v.second == 5)
    @assert(v.third == 9)
    @assert(v.drops == 8)
    @assert(v.dropTrace == 201070605040309)
}

#test
{
    let v = intrinsicAutoDropBreakScopeInfo()
    @assert(v.first == 4)
    @assert(v.second == 7)
    @assert(v.third == 2)
    @assert(v.drops == 7)
    @assert(v.dropTrace == 7060504030201)
}

#test
{
    let v = intrinsicAutoDropSwitchReturnInfo()
    @assert(v.first == 2)
    @assert(v.second == 6)
    @assert(v.third == 7)
    @assert(v.drops == 5)
    @assert(v.dropTrace == 807060201)
}

#test
{
    let v = intrinsicAutoDropCatchResumeInfo()
    @assert(v.first == 55)
    @assert(v.second == 9)
    @assert(v.third == 1)
    @assert(v.drops == 5)
    @assert(v.dropTrace == 54398)
}

#test
{
    let v = intrinsicAutoDropTryCatchLoopInfo()
    @assert(v.first == 5)
    @assert(v.second == 1)
    @assert(v.third == 17)
    @assert(v.drops == 9)
    @assert(v.dropTrace == 321654879)
}

#test
{
    let v = intrinsicAutoDropSwitchFallthroughInfo()
    @assert(v.first == 1)
    @assert(v.second == 3)
    @assert(v.third == 7)
    @assert(v.drops == 7)
    @assert(v.dropTrace == 2154376)
}

#test
{
    let v = intrinsicAutoDropIfVarReturnInfo()
    @assert(v.first == 2)
    @assert(v.second == 3)
    @assert(v.third == 6)
    @assert(v.drops == 6)
    @assert(v.dropTrace == 654321)
}

#test
{
    let v = intrinsicAutoDropIfVarElseInfo()
    @assert(v.first == 6)
    @assert(v.second == 1)
    @assert(v.third == 9)
    @assert(v.drops == 4)
    @assert(v.dropTrace == 3219)
}

#test
{
    let v = intrinsicAutoDropWithVarReturnInfo()
    @assert(v.first == 7)
    @assert(v.second == 4)
    @assert(v.third == 8)
    @assert(v.drops == 5)
    @assert(v.dropTrace == 65487)
}

#test
{
    let v = intrinsicAutoDropShadowInfo()
    @assert(v.first == 9)
    @assert(v.second == 2)
    @assert(v.third == 5)
    @assert(v.drops == 6)
    @assert(v.dropTrace == 321549)
}

#test
{
    let scalarTrace = intrinsicInitRuntimeCountScalarInfo()
    @assert(scalarTrace == 9006)

    let structTrace = intrinsicInitRuntimeCountStructInfo()
    @assert(structTrace == 9116)

    let closureTrace = intrinsicInitRuntimeCountClosureInfo()
    @assert(closureTrace == 411)
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
    @assert(intrinsicInitStrictEnumInfo())
    @assert(intrinsicInitStrictIntInfo())
    @assert(intrinsicInitStrictFloatInfo())
    @assert(intrinsicInitStrictPointerInfo())
    @assert(intrinsicInitStrictStringInfo())
    @assert(IntrinsicRunStrictInts[0] == cast(IntrinsicStrictIntAlias) 11)
    @assert(IntrinsicRunStrictInts[1] == cast(IntrinsicStrictIntAlias) 13)
    @assert(IntrinsicRunStrictFloats[0] == cast(IntrinsicStrictFloatAlias) 1.25)
    @assert(IntrinsicRunStrictFloats[1] == cast(IntrinsicStrictFloatAlias) 2.5)
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
