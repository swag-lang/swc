#global moduleprivate
using Swag

namespace GenericForeachLazyCodegen
{
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

    struct(T) BufferBox
    {
        allocator: IAllocator
        buffer:    [*] T
        count:     u64
        capacity:  u64
    }

    impl BufferBox
    {
        mtd reserve(newCapacity: u64)
        {
            if newCapacity <= .capacity do
                return

            .buffer = cast([*] T) helperRealloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator)
            .capacity = newCapacity
        }

        #[Inline]
        mtd toSlice()->[..] T
        {
            return @mkslice(.buffer, .count)
        }

        #[Inline]
        mtd const toSlice()->const [..] T
        {
            return @mkslice(.buffer, .count)
        }

        mtd add(value: T)
        {
            .buffer[.count] = value
            .count += 1
        }

        mtd free()
        {
            helperFree(.buffer, .capacity * #sizeof(T), .allocator)
            .buffer = null
            .count, .capacity = 0
        }
    }

    struct(T) LoopBox
    {
        values: BufferBox'T
    }

    impl LoopBox
    {
        #[Swag.NoInline]
        mtd whereIndexSum(skip: T)->u64
        {
            var total = 0'u64
            foreach value, index in .values.toSlice() where value != skip do
                total += index + 1
            return total
        }

        #[Swag.NoInline]
        mtd const constWhereCount(skip: T)->u64
        {
            var total = 0'u64
            foreach value in .values.toSlice() where value != skip do
                total += 1
            return total
        }

        #[Swag.NoInline]
        mtd reverseIndexCode()->u64
        {
            var code = 0'u64
            foreach #reverse _value, index in .values.toSlice() do
                code = code * 10 + index + 1
            return code
        }

        #[Swag.NoInline]
        mtd nonNullIndexSum()->u64
        {
            var total = 0'u64
            foreach &value, index in .values.toSlice() where dref value != null do
                total += index + 1
            return total
        }

        mtd free()
        {
            .values.free()
        }
    }

    func makeIntBox()->LoopBox's32
    {
        var box: LoopBox's32
        box.values.reserve(4)
        box.values.add(3)
        box.values.add(5)
        box.values.add(3)
        box.values.add(7)
        return box
    }

    func makeBoolBox()->LoopBox'bool
    {
        var box: LoopBox'bool
        box.values.reserve(4)
        box.values.add(true)
        box.values.add(false)
        box.values.add(true)
        box.values.add(false)
        return box
    }

    func allocS32(value: s32)->*s32
    {
        let ptr = cast(*s32) @alloc(#sizeof(s32))
        dref ptr = value
        return ptr
    }

    func makePtrBox()->LoopBox'(*s32)
    {
        var box: LoopBox'(*s32)
        box.values.reserve(3)
        box.values.add(allocS32(4))
        box.values.add(null)
        box.values.add(allocS32(9))
        return box
    }

    func compileTimeIntSuite()->bool
    {
        var box = makeIntBox()
        let ok = box.whereIndexSum(3) == 6 and
                 box.constWhereCount(7) == 3 and
                 box.reverseIndexCode() == 4321
        box.free()
        return ok
    }

    func compileTimeBoolSuite()->bool
    {
        var box = makeBoolBox()
        let ok = box.whereIndexSum(false) == 4 and
                 box.constWhereCount(true) == 2 and
                 box.reverseIndexCode() == 4321
        box.free()
        return ok
    }

    func runRuntimeSuite()->bool
    {
        var ints = makeIntBox()
        let intsOk = ints.whereIndexSum(3) == 6 and
                     ints.constWhereCount(7) == 3 and
                     ints.reverseIndexCode() == 4321
        ints.free()

        var bools = makeBoolBox()
        let boolsOk = bools.whereIndexSum(false) == 4 and
                      bools.constWhereCount(true) == 2 and
                      bools.reverseIndexCode() == 4321
        bools.free()

        var ptrs = makePtrBox()
        let ptrsOk = ptrs.nonNullIndexSum() == 4
        foreach ptr in ptrs.values.toSlice() where ptr != null do
            @free(ptr)
        ptrs.free()

        return intsOk and boolsOk and ptrsOk
    }
}

const IntSuiteOk  = #run GenericForeachLazyCodegen.compileTimeIntSuite()
const BoolSuiteOk = #run GenericForeachLazyCodegen.compileTimeBoolSuite()
const RunSuiteOk  = #run GenericForeachLazyCodegen.runRuntimeSuite()

#test
{
    @assert(IntSuiteOk)
    @assert(BoolSuiteOk)
    @assert(RunSuiteOk)
    @assert(GenericForeachLazyCodegen.runRuntimeSuite())
}
