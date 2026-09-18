#global export

using Swag

// A key stored in a [[Core.HashSet]].
struct(K) HashSetEntry
{
    hash: u32

    public
    {
        readonly key: K     // The key itself.
    }
}

// An open-addressing hash set of unique keys.
//
// Lookups, insertions, and removals take expected constant time. The set grows by rehashing, which
// moves every key and invalidates every entry pointer borrowed from it.
struct(K) HashSet
{
    // Special hash values to indicate the state of a slot in the table.
    #[Swag.NoDoc]
    const HASH_FREE = 0'u32
    #[Swag.NoDoc]
    const HASH_DELETED = 1'u32
    #[Swag.NoDoc]
    const HASH_FIRST = 2'u32

    internal allocator: IAllocator?

    // Sizes are reported, never set: the set grows itself when it needs to.

    public readonly
    {
        count:    u64     // The number of valid elements currently in the set.
        capacity: u64     // The total number of slots in the hash table.
    }

    // Open-addressing state. The layout is an implementation choice: reaching into it from
    // outside would tie callers to the probing scheme and the load factor.

    private
    {
        table:   [*] HashSetEntry?     // Contiguous memory block for the slots.
        deleted: u64                   // The number of slots marked as deleted.
    }
}

// Iterates a borrowed hash set by descending storage slot.
#[Swag.Opaque]
struct(K) ReversedHashSet
{
    source: const *HashSet'K
}

impl ReversedHashSet
{
    // Visits borrowed set elements in descending storage-slot order.
    #[Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(key))
    {
        let table  = .source.constTablePtr()
        var remain = .source.count
        #scope(Up)
        for offset in .source.capacity
        {
            let tableIndex = .source.capacity - offset - 1
            if table[tableIndex].hash < 2'u32 do
                continue

            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, key = cast(*K) &table[tableIndex].key, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) do
                    #inject(stmt, key = cast(const *K) &table[tableIndex].key, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, key = table[tableIndex].key, break = break to Up, continue = break to Down)
            }

            remain -= 1
            if not remain do
                break
        }
    }
}

impl HashSet
{
    #[Swag.NoDoc]
    func normalizeCapacity(newCapacity: u64)->u64
    {
        var result = 32'u64
        let target = Math.max(newCapacity, result)
        while result < target do
            result <<= 1
        return result
    }

    #[Swag.NoDoc]
    mtd tablePtr()->[*] HashSetEntry => .table orelse cast([*] HashSetEntry'(K)) 1'u64

    #[Swag.NoDoc]
    mtd const constTablePtr()->const [*] HashSetEntry => cast(const [*] HashSetEntry'(K)) (.table orelse cast([*] HashSetEntry'(K)) 1'u64)

    // Returns the number of elements in the set.
    #[Inline]
    mtd const opCount()->u64 => .count

    // Returns whether the set contains no elements.
    #[Inline]
    mtd const isEmpty()->bool => .count == 0

    // Drops every key and releases the slots.
    mtd opDrop()
    {
        .free()
    }

    // Replaces the content with copies of the keys in `slice`, ignoring duplicates.
    mtd opSet(slice: const [..] K)
    {
        .clear()
        for v in slice do
            .add(v)
    }

    // Gives a copied set its own slots holding copies of the keys.
    mtd opPostCopy()
    {
        if not .table do
            return

        if not .allocator do
            .allocator = Swag.getContext().allocator

        let oldTable = .tablePtr()
        let newTable = cast([*] HashSetEntry'(K)) Memory.alloc(.capacity * #sizeof(HashSetEntry'(K)), .allocator)
        #static if Reflection.hasDynamicStorage(HashSetEntry'(K)) do
            Swag.init(newTable, .capacity)
        else do
            Memory.clear(newTable, .capacity * #sizeof(HashSetEntry'(K)))
        #static if Reflection.hasPostCopy(K)
        {
            for i in .capacity
            {
                let hashVal = oldTable[i].hash
                if hashVal < HashSet.HASH_DELETED do
                    continue

                newTable[i].hash = hashVal
                newTable[i].key  = #nodrop oldTable[i].key
            }
        }
        else
        {
            Memory.copy(newTable, oldTable, .capacity * #sizeof(HashSetEntry'(K)))
        }

        .table = newTable
    }

    // Visits every key in storage-slot order, binding it to `key`.
    //
    // The order is unspecified and changes when the set grows. Visiting by address binds a mutable
    // pointer; otherwise a struct key is bound through a constant pointer and any other by value.
    #[Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(key))
    {
        if not .count do
            return

        let table  = .constTablePtr()
        var remain = .count
        #scope(Up)
        for tableIndex in .capacity
        {
            if table[tableIndex].hash < HashSet.HASH_FIRST do
                continue

            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, key = cast(*K) &table[tableIndex].key, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(K) do
                    #inject(stmt, key = cast(const *K) &table[tableIndex].key, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, key = table[tableIndex].key, break = break to Up, continue = break to Down)
            }

            remain -= 1
            if not remain do
                break
        }
    }

    // Returns an immutable zero-allocation view that scans occupied slots in reverse order.
    mtd const reversed()->ReversedHashSet'K => {source: me}

    // Returns the hash of `key`, lifted above the reserved free and deleted slot markers.
    //
    // Only the two reserved values are lifted, never a whole bit: forcing a bit on
    // would make every starting probe index share it, so half of the slots could
    // only ever be reached by probing.
    #[Inline, Swag.NoDoc]
    func hashKey(key: K)->u32
    {
        let hashVal = Hash.hash32(key)
        return hashVal < HashSet.HASH_FIRST ? HashSet.HASH_FIRST : hashVal
    }

    // Drops every key, releases the slots, and leaves the set empty.
    mtd free()
    {
        if not .table do
            return
        let table = .tablePtr()

        // Deleted slots still hold their key until they are reused.
        #static if Reflection.hasDrop(#typeof(K))
        {
            for i in .capacity
            {
                if table[i].hash >= HashSet.HASH_DELETED do
                    Swag.drop(&table[i].key)
            }
        }

        Memory.free(table, .capacity * #sizeof(HashSetEntry'(K)), .allocator)
        .table = null
        .count, .capacity, .deleted = 0
    }

    // Doubles the capacity when the used slots, deleted ones included, reach half of it.
    #[Swag.NoDoc]
    mtd grow()
    {
        // Linear probing degrades sharply past half full: a failed lookup averages
        // 2.5 probes at a 50% load factor, but 8.5 probes at 75%.
        if .capacity != 0 and .capacity - (.count + .deleted) > .capacity / 2 do
            return

        let newCapacity = .capacity * 2
        .reserve(newCapacity)
    }

    // Grows the set to at least `newCapacity` slots, rehashing every key.
    //
    // The slot count is rounded up to a power of two of at least 32. Requests at or below the
    // current capacity do nothing.
    mtd reserve(newCapacity: u64)
    {
        let reqCapacity = normalizeCapacity(newCapacity)
        if reqCapacity <= .capacity do
            return

        let oldTable = .table
        .count, .deleted = 0
        let newCapacityBytes = reqCapacity * #sizeof(HashSetEntry'(K))

        if not .allocator do
            .allocator = Swag.getContext().allocator
        .table = cast([*] HashSetEntry'(K)) Memory.alloc(newCapacityBytes, .allocator)
        let table = .tablePtr()

        // Every slot starts free, which is a zero hash.
        #static if Reflection.hasDynamicStorage(HashSetEntry'(K)) do
            Swag.init(table, reqCapacity)
        else do
            Memory.clear(table, newCapacityBytes)

        // Relocate the live keys into the new slots and drop the deleted ones.
        let oldCapacity = .capacity
        .capacity = reqCapacity
        let oldTablePtr = oldTable orelse cast([*] HashSetEntry'(K)) 1'u64
        for i in oldCapacity
        {
            let h = oldTablePtr[i].hash
            if h >= HashSet.HASH_FIRST
            {
                .emplaceInternal(h, &oldTablePtr[i].key)
            }
            elif h == HashSet.HASH_DELETED
            {
                Swag.drop(&oldTablePtr[i].key)
            }
        }

        Memory.free(oldTable, oldCapacity * #sizeof(HashSetEntry'(K)), .allocator)
    }

    // Returns the slot of `key`, or the slot where it would be inserted, probing linearly from `idx`.
    //
    // A deleted slot met on the way is reused when the key is absent.
    //
    // Both loops test the cached hash first: an occupied slot that does not match is by far
    // the most frequent outcome, and it must cost a single compare. A set that has never seen
    // a removal takes the shorter loop, which has no deleted slot to remember.
    #[Swag.NoDoc]
    mtd getNewIndex(key: K, idx: u64, hashVal: u64)->u64
    {
        let mask  = .capacity - 1
        var index = idx
        let table = .tablePtr()

        if not .deleted
        {
            for
            {
                let entryHash = table[index].hash
                if entryHash == hashVal
                {
                    if table[index].key == key do
                        return index
                }
                elif entryHash == HashSet.HASH_FREE do
                    return index

                index = (index + 1) & mask
            }
        }

        var firstDeleted = Swag.U64.Max
        for
        {
            let entryHash = table[index].hash
            if entryHash == hashVal
            {
                if table[index].key == key do
                    return index
            }
            elif entryHash < HashSet.HASH_FIRST
            {
                if entryHash == HashSet.HASH_FREE do
                    return firstDeleted != Swag.U64.Max ? firstDeleted : index
                if firstDeleted == Swag.U64.Max do
                    firstDeleted = index
            }

            index = (index + 1) & mask
        }
    }

    // Adds `key` unless it is already present, and returns its entry.
    //
    // The key is copied; pass it with `#move` to move it instead.
    #[Discardable]
    mtd add(key: #fwd K)->*HashSetEntry
    {
        .grow()

        let hashVal = hashKey(key)
        var index   = cast(u64) hashVal & (.capacity - 1)
        let table   = .tablePtr()

        index = .getNewIndex(key, index, hashVal)
        if table[index].hash >= HashSet.HASH_FIRST do
            return table + index

        if table[index].hash == HashSet.HASH_FREE
        {
            table[index].key = #nodrop #fwd key
        }
        else
        {
            if table[index].hash == HashSet.HASH_DELETED do
                .deleted -= 1
            table[index].key = #fwd key
        }

        table[index].hash = hashVal
        .count += 1
        return table + index
    }

    // Relocates `key` into the set under a precomputed hash.
    #[Discardable, Swag.NoDoc]
    mtd emplaceInternal(hashVal: u32, key: *K)->*HashSetEntry
        where Reflection.canCopy(#typeof(K))
    {
        .grow()

        var index = cast(u64) hashVal & (.capacity - 1)
        let table = .tablePtr()

        index = .getNewIndex(key[], index, hashVal)
        if table[index].hash >= HashSet.HASH_FIRST do
            return table + index

        if table[index].hash == HashSet.HASH_FREE
        {
            table[index].key = #relocate key[]
        }
        else
        {
            if table[index].hash == HashSet.HASH_DELETED do
                .deleted -= 1
            Swag.drop(&table[index].key)
            table[index].key = #relocate key[]
        }

        table[index].hash = hashVal
        .count += 1
        return table + index
    }

    // Adds `key` when it is absent or removes it when present, and returns whether it is now present.
    //
    // The key is copied when inserted; pass it with `#move` to move it instead.
    #[Discardable]
    mtd toggle(key: #fwd K)->bool
    {
        .grow()

        let hashVal      = hashKey(key)
        let mask         = .capacity - 1
        var firstDeleted = Swag.U64.Max
        var index        = cast(u64) hashVal & mask
        let table        = .tablePtr()

        for
        {
            let entryHash = table[index].hash
            if entryHash == HashSet.HASH_FREE
            {
                let targetIndex = firstDeleted != Swag.U64.Max ? firstDeleted : index
                if table[targetIndex].hash == HashSet.HASH_FREE
                {
                    table[targetIndex].key = #nodrop #fwd key
                }
                else
                {
                    .deleted -= 1
                    table[targetIndex].key = #fwd key
                }

                table[targetIndex].hash = hashVal
                .count += 1
                return true
            }

            if entryHash == HashSet.HASH_DELETED and firstDeleted == Swag.U64.Max
            {
                firstDeleted = index
            }
            elif entryHash == hashVal and table[index].key == key
            {
                table[index].hash = HashSet.HASH_DELETED
                .count   -= 1
                .deleted += 1
                return false
            }

            index = (index + 1) & mask
        }
    }

    // Removes `key`; does nothing when it is absent.
    //
    // The slot is only marked as deleted: its key is dropped when the slot is reused, when the set
    // grows, or when it is cleared or freed.
    mtd remove(key: K)
    {
        if not .table do
            return

        let hashVal = hashKey(key)
        let mask    = .capacity - 1
        var index   = cast(u64) hashVal & mask
        let table   = .tablePtr()

        while table[index].hash
        {
            if table[index].hash == hashVal and table[index].key == key
            {
                table[index].hash = HashSet.HASH_DELETED
                .count   -= 1
                .deleted += 1
                return
            }

            index = (index + 1) & mask
        }
    }

    // Returns whether the set contains `key`.
    mtd const contains(key: K)->bool
    {
        if not .table do
            return false

        let hashVal = hashKey(key)
        let mask    = .capacity - 1
        var index   = cast(u64) hashVal & mask
        let table   = .constTablePtr()

        while table[index].hash
        {
            if table[index].hash == hashVal and table[index].key == key do
                return true
            index = (index + 1) & mask
        }

        return false
    }

    // Drops every key and leaves the set empty, keeping its slots for reuse.
    mtd clear()
    {
        // Free every slot, dropping what live and deleted slots still hold.
        if .count or .deleted
        {
            let table = .tablePtr()
            for i in .capacity
            {
                let hashval = table[i].hash
                if hashval >= HashSet.HASH_DELETED do
                    Swag.drop(&table[i].key)

                if hashval == HashSet.HASH_DELETED do
                    .deleted -= 1
                elif hashval >= HashSet.HASH_FIRST do
                    .count -= 1
                table[i].hash = HashSet.HASH_FREE

                // The remaining slots are already free once no live or deleted slot is left.
                if not .count and not .deleted do
                    break
            }
        }
    }
}

impl StrConv.IConvert for HashSet
{
    mtd const impl convert(buf: *ConcatBuffer, convFormat: StrConv.ConvertFormat, strFormat: string?)
    {
        buf.addBytes("[")
        var first = true
        for k in me
        {
            if not first do
                buf.addBytes(", ")
            first = false
            StrConv.convert'K(buf, k, convFormat, strFormat)
        }

        buf.addBytes("]")
    }
}
