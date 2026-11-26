#global internal
using Swag

namespace GenericMkSliceLazyCodegen
{
    func helperFree(buffer: [*] void?, size: u64, allocator: IAllocator? = null)
    {
        if not buffer
        {
            return
        }

        var req: AllocatorRequest
        req.size    = size
        req.address = buffer

        let talloc = unwrap (allocator orelse Swag.getContext().allocator)
        talloc.free(&req)
    }

    func helperRealloc(buffer: [*] void?, newSize: u64, oldSize: u64, allocator: IAllocator? = null)->[*] void?
    {
        var req: AllocatorRequest
        req.address = buffer
        req.size    = newSize
        req.oldSize = oldSize

        let talloc = unwrap (allocator orelse Swag.getContext().allocator)
        talloc.realloc(&req)
        return req.address
    }

    struct Pair
    {
        left:  s32
        right: s32
    }

    struct Triple
    {
        first:  u8
        second: u16
        third:  u32
    }

    struct(T) BufferBox
    {
        allocator: IAllocator?
        buffer:    [*] T?
        count:     u64
        capacity:  u64
    }

    impl BufferBox
    {
        mtd reserve(newCapacity: u64)
        {
            if newCapacity <= .capacity
            {
                return
            }

            .buffer   = cast([*] T?, helperRealloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator))
            .capacity = newCapacity
        }

        #[Inline]
        mtd toSlice()->[..] T
        {
            return Swag.makeSlice(.buffer, .count)
        }

        #[Inline]
        mtd const toSlice()->const [..] T
        {
            return Swag.makeSlice(.buffer, .count)
        }

        #[Inline]
        mtd opCast()->[..] T
        {
            return .toSlice()
        }

        #[Inline]
        mtd const opCast()->const [..] T
        {
            return .toSlice()
        }

        mtd add(value: T)
        {
            let buf = unwrap .buffer
            buf[.count] = value
            .count      += 1
        }

        mtd free()
        {
            helperFree(.buffer, .capacity * #sizeof(T), .allocator)
            .buffer = null
            .count, .capacity = 0
        }
    }

    struct(T) Box
    {
        values: BufferBox!{T}
    }

    impl Box
    {
        #[Swag.NoInline]
        mtd mutableCount()->u64
        {
            let slice = .values.toSlice()
            return slice.count
        }

        #[Swag.NoInline]
        mtd const constCount()->u64
        {
            let slice = .values.toSlice()
            return slice.count
        }

        #[Swag.NoInline]
        mtd iteratedCount()->u64
        {
            var total = 0_u64
            for _item in .values.toSlice()
            {
                total += 1
            }
            return total
        }
    }

    struct(T) Nested
    {
        box: Box!{T}
    }

    impl Nested
    {
        #[Swag.NoInline]
        mtd totalCount()->u64
        {
            return .box.mutableCount() + .box.constCount() + .box.iteratedCount()
        }
    }

    #[Swag.NoInline]
    func(T, N: s32) directCount(items: [N] T)->u64
    {
        var values: BufferBox!{T}
        values.reserve(cast(u64, N))
        for item in items
        {
            values.add(item)
        }

        let count = (values.toSlice()).count
        values.free()
        return count
    }

    #[Swag.NoInline]
    func(T, N: s32) nestedCount(items: [N] T)->u64
    {
        var nested: Nested!{T}
        nested.box.values.reserve(cast(u64, N))
        for item in items
        {
            nested.box.values.add(item)
        }

        let count = nested.totalCount()
        nested.box.values.free()
        return count
    }

    func runSuite()->bool
    {
        return directCount!{s32, 4}([1, 2, 3, 4]) == 4 and
               nestedCount!{s32, 4}([1, 2, 3, 4]) == 12 and
               directCount!{u64, 3}([11_u64, 22_u64, 33_u64]) == 3 and
               nestedCount!{u64, 3}([11_u64, 22_u64, 33_u64]) == 9 and
               directCount!{bool, 2}([true, false]) == 2 and
               nestedCount!{bool, 2}([true, false]) == 6 and
               directCount!{Pair, 2}([{left: 1, right: 2}, {left: 3, right: 4}]) == 2 and
               nestedCount!{Pair, 2}([{left: 1, right: 2}, {left: 3, right: 4}]) == 6 and
               directCount!{Triple, 3}([{first: 1_u8, second: 2_u16, third: 3_u32}, {first: 4_u8, second: 5_u16, third: 6_u32}, {first: 7_u8, second: 8_u16, third: 9_u32}]) == 3 and
               nestedCount!{Triple, 3}([{first: 1_u8, second: 2_u16, third: 3_u32}, {first: 4_u8, second: 5_u16, third: 6_u32}, {first: 7_u8, second: 8_u16, third: 9_u32}]) == 9 and
               directCount!{[2]u8, 2}([[1_u8, 2_u8], [3_u8, 4_u8]]) == 2 and
               nestedCount!{[2]u8, 2}([[1_u8, 2_u8], [3_u8, 4_u8]]) == 6
    }
}

const DirectS32Ok    = #run GenericMkSliceLazyCodegen.directCount!{s32, 4}([1, 2, 3, 4]) == 4
const NestedS32Ok    = #run GenericMkSliceLazyCodegen.nestedCount!{s32, 4}([1, 2, 3, 4]) == 12
const DirectU64Ok    = #run GenericMkSliceLazyCodegen.directCount!{u64, 3}([11_u64, 22_u64, 33_u64]) == 3
const NestedU64Ok    = #run GenericMkSliceLazyCodegen.nestedCount!{u64, 3}([11_u64, 22_u64, 33_u64]) == 9
const DirectBoolOk   = #run GenericMkSliceLazyCodegen.directCount!{bool, 2}([true, false]) == 2
const NestedBoolOk   = #run GenericMkSliceLazyCodegen.nestedCount!{bool, 2}([true, false]) == 6
const DirectPairOk   = #run GenericMkSliceLazyCodegen.directCount!{GenericMkSliceLazyCodegen.Pair, 2}([{left: 1, right: 2}, {left: 3, right: 4}]) == 2
const NestedPairOk   = #run GenericMkSliceLazyCodegen.nestedCount!{GenericMkSliceLazyCodegen.Pair, 2}([{left: 1, right: 2}, {left: 3, right: 4}]) == 6
const DirectTripleOk = #run GenericMkSliceLazyCodegen.directCount!{GenericMkSliceLazyCodegen.Triple, 3}([{first: 1_u8, second: 2_u16, third: 3_u32}, {first: 4_u8, second: 5_u16, third: 6_u32}, {first: 7_u8, second: 8_u16, third: 9_u32}]) == 3
const NestedTripleOk = #run GenericMkSliceLazyCodegen.nestedCount!{GenericMkSliceLazyCodegen.Triple, 3}([{first: 1_u8, second: 2_u16, third: 3_u32}, {first: 4_u8, second: 5_u16, third: 6_u32}, {first: 7_u8, second: 8_u16, third: 9_u32}]) == 9
const DirectArrayOk  = #run GenericMkSliceLazyCodegen.directCount!{[2]u8, 2}([[1_u8, 2_u8], [3_u8, 4_u8]]) == 2
const NestedArrayOk  = #run GenericMkSliceLazyCodegen.nestedCount!{[2]u8, 2}([[1_u8, 2_u8], [3_u8, 4_u8]]) == 6
const SuiteOk        = #run GenericMkSliceLazyCodegen.runSuite()

#test
{
    Swag.require(DirectS32Ok)
    Swag.require(NestedS32Ok)
    Swag.require(DirectU64Ok)
    Swag.require(NestedU64Ok)
    Swag.require(DirectBoolOk)
    Swag.require(NestedBoolOk)
    Swag.require(DirectPairOk)
    Swag.require(NestedPairOk)
    Swag.require(DirectTripleOk)
    Swag.require(NestedTripleOk)
    Swag.require(DirectArrayOk)
    Swag.require(NestedArrayOk)
    Swag.require(SuiteOk)
    Swag.require(GenericMkSliceLazyCodegen.runSuite())
}
