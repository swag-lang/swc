#global internal
using Swag

namespace GenericReallocDefaultArgsCodegen
{
    var gLastCaller:       SourceCodeLocation
    var gLastHintWasNull = false
    var gLastAlignment   = 1'u32
    var gReallocCallCount = 0'u64

    func resetTracker()
    {
        var zero: SourceCodeLocation
        gLastCaller = zero
        gLastHintWasNull = false
        gLastAlignment = 1
        gReallocCallCount = 0
    }

    func trackerMatches(expectedCalls: u64)->bool
    {
        return gReallocCallCount == expectedCalls and
               gLastHintWasNull and
               gLastAlignment == 0 and
               gLastCaller.fileName != null and
               gLastCaller.funcName != null
    }

    func expectedCapacity(firstGrowth, count: u64)->u64
    {
        if count == 0 do
            return 0
        if count <= firstGrowth do
            return firstGrowth
        if count <= firstGrowth * 2 do
            return firstGrowth * 2
        if count <= firstGrowth * 4 do
            return firstGrowth * 4
        return firstGrowth * 8
    }

    func expectedStableCode(count, capacity: u64)->u64
    {
        return capacity * 10 + count + count * (count + 1) / 2
    }

    namespace LocalMemory
    {
        func free(buffer: [*] void, size: u64, allocator: IAllocator = null, hint: string = null, loc = #callerlocation)
        {
            if !buffer do
                return

            var req: AllocatorRequest
            req.callerLoc = loc
            req.hint = hint
            req.mode = .Free
            req.size = size
            req.address = buffer

            let talloc = allocator orelse @getcontext().allocator
            talloc.req(&req)
        }

        func realloc(buffer: [*] void, newSize: u64, oldSize: u64, allocator: IAllocator = null, alignment: u16 = 0, hint: string = null, loc = #callerlocation)->[*] void
        {
            gLastCaller = loc
            gLastHintWasNull = hint == null
            gLastAlignment = alignment
            gReallocCallCount += 1

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
    }

    struct Pair
    {
        left:  s32
        right: s32
    }

    struct(T) Buffer
    {
        allocator: IAllocator
        buffer:    [*] T
        count:     u64
        capacity:  u64
    }

    impl Buffer
    {
        mtd realloc(newCapacity: u64)
        {
            if .allocator == null do
                .allocator = @getcontext().allocator

            if newCapacity == 0
            {
                LocalMemory.free(.buffer, .capacity * #sizeof(T), .allocator)
                .buffer = null
                .capacity = 0
                return
            }

            .buffer = cast([*] T) LocalMemory.realloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator)
            .capacity = newCapacity
        }

        mtd reserve(newCapacity: u64)
        {
            if newCapacity <= .capacity do
                return
            .realloc(newCapacity)
        }

        mtd reserveNamed(newCapacity: u64)
        {
            if newCapacity <= .capacity do
                return

            if .allocator == null do
                .allocator = @getcontext().allocator

            .buffer = cast([*] T) LocalMemory.realloc(buffer: .buffer, newSize: newCapacity * #sizeof(T), oldSize: .capacity * #sizeof(T), allocator: .allocator)
            .capacity = newCapacity
        }

        mtd append(value: T)
        {
            if .count == .capacity do
                .reserve(.capacity ? .capacity * 2 : 2)
            .buffer[.count] = value
            .count += 1
        }

        mtd appendNamed(value: T)
        {
            if .count == .capacity do
                .reserveNamed(.capacity ? .capacity * 2 : 3)
            .buffer[.count] = value
            .count += 1
        }

        #[Inline]
        mtd toSlice()->[..] T
        {
            return @mkslice(.buffer, .count)
        }

        #[Swag.NoInline]
        mtd stableCode()->u64
        {
            var total = .capacity * 10 + .count
            foreach _value, index in .toSlice() do
                total += index + 1
            return total
        }

        mtd free()
        {
            LocalMemory.free(.buffer, .capacity * #sizeof(T), .allocator)
            .buffer = null
            .count, .capacity = 0
        }
    }

    struct(T) Nested
    {
        values: Buffer'T
    }

    impl Nested
    {
        #[Swag.NoInline]
        mtd runMixed(a, b, c: T)->bool
        {
            resetTracker()
            .values.append(a)
            .values.append(b)
            .values.appendNamed(c)

            return .values.count == 3 and
                   .values.capacity == 4 and
                   .values.stableCode() == expectedStableCode(3, 4) and
                   trackerMatches(2)
        }

        mtd free()
        {
            .values.free()
        }
    }

    func(T, N: s32) runPositional(items: [N] T)->bool
    {
        resetTracker()

        var values: Buffer'T
        foreach item in items do
            values.append(item)

        let count = cast(u64) N
        let ok = values.count == count and
                 @countof(values.toSlice()) == count and
                 values.capacity == expectedCapacity(2, count) and
                 values.stableCode() == expectedStableCode(count, expectedCapacity(2, count)) and
                 trackerMatches(count > 2 ? 2 : 1)

        values.free()
        return ok
    }

    func(T, N: s32) runNamed(items: [N] T)->bool
    {
        resetTracker()

        var values: Buffer'T
        foreach item in items do
            values.appendNamed(item)

        let count = cast(u64) N
        let ok = values.count == count and
                 @countof(values.toSlice()) == count and
                 values.capacity == expectedCapacity(3, count) and
                 values.stableCode() == expectedStableCode(count, expectedCapacity(3, count)) and
                 trackerMatches(count > 3 ? 2 : 1)

        values.free()
        return ok
    }

    func(T) runNested(a, b, c: T)->bool
    {
        var nested: Nested'T
        let ok = nested.runMixed(a, b, c)
        nested.free()
        return ok
    }

    func runSuite()->bool
    {
        return runPositional'(s32, 4)([1, 2, 3, 4]) and
               runNamed'(s32, 4)([1, 2, 3, 4]) and
               runPositional'(bool, 2)([true, false]) and
               runNamed'(bool, 3)([true, false, true]) and
               runPositional'(Pair, 3)([{left: 1, right: 2}, {left: 3, right: 4}, {left: 5, right: 6}]) and
               runNamed'(Pair, 4)([{left: 1, right: 2}, {left: 3, right: 4}, {left: 5, right: 6}, {left: 7, right: 8}]) and
               runPositional'([2]u8, 3)([[1'u8, 2'u8], [3'u8, 4'u8], [5'u8, 6'u8]]) and
               runNamed'([2]u8, 4)([[1'u8, 2'u8], [3'u8, 4'u8], [5'u8, 6'u8], [7'u8, 8'u8]]) and
               runNested'(s32)(1, 2, 3) and
               runNested'(Pair)({left: 10, right: 11}, {left: 12, right: 13}, {left: 14, right: 15})
    }
}

const ReallocPositionalS32Ok   = #run GenericReallocDefaultArgsCodegen.runPositional'(s32, 4)([1, 2, 3, 4])
const ReallocNamedS32Ok        = #run GenericReallocDefaultArgsCodegen.runNamed'(s32, 4)([1, 2, 3, 4])
const ReallocPositionalBoolOk  = #run GenericReallocDefaultArgsCodegen.runPositional'(bool, 2)([true, false])
const ReallocNamedBoolOk       = #run GenericReallocDefaultArgsCodegen.runNamed'(bool, 3)([true, false, true])
const ReallocPositionalPairOk  = #run GenericReallocDefaultArgsCodegen.runPositional'(GenericReallocDefaultArgsCodegen.Pair, 3)([{left: 1, right: 2}, {left: 3, right: 4}, {left: 5, right: 6}])
const ReallocNamedPairOk       = #run GenericReallocDefaultArgsCodegen.runNamed'(GenericReallocDefaultArgsCodegen.Pair, 4)([{left: 1, right: 2}, {left: 3, right: 4}, {left: 5, right: 6}, {left: 7, right: 8}])
const ReallocPositionalArrayOk = #run GenericReallocDefaultArgsCodegen.runPositional'([2]u8, 3)([[1'u8, 2'u8], [3'u8, 4'u8], [5'u8, 6'u8]])
const ReallocNamedArrayOk      = #run GenericReallocDefaultArgsCodegen.runNamed'([2]u8, 4)([[1'u8, 2'u8], [3'u8, 4'u8], [5'u8, 6'u8], [7'u8, 8'u8]])
const ReallocNestedS32Ok       = #run GenericReallocDefaultArgsCodegen.runNested'(s32)(1, 2, 3)
const ReallocNestedPairOk      = #run GenericReallocDefaultArgsCodegen.runNested'(GenericReallocDefaultArgsCodegen.Pair)({left: 10, right: 11}, {left: 12, right: 13}, {left: 14, right: 15})
const ReallocRunSuiteOk        = #run GenericReallocDefaultArgsCodegen.runSuite()

#test
{
    @assert(ReallocPositionalS32Ok)
    @assert(ReallocNamedS32Ok)
    @assert(ReallocPositionalBoolOk)
    @assert(ReallocNamedBoolOk)
    @assert(ReallocPositionalPairOk)
    @assert(ReallocNamedPairOk)
    @assert(ReallocPositionalArrayOk)
    @assert(ReallocNamedArrayOk)
    @assert(ReallocNestedS32Ok)
    @assert(ReallocNestedPairOk)
    @assert(ReallocRunSuiteOk)
    @assert(GenericReallocDefaultArgsCodegen.runSuite())
}
